# Terraform — VM Azure con state remoto (paso a paso)

Este es el laboratorio del módulo 4. Vamos a provisionar en Azure una VM `Standard_B2s` (default; ver §0) que descargue, vía Docker, la imagen del trainer construida por la GitHub Action y la ejecute contra un **Storage Account creado por el propio Terraform**.

Todo el ciclo de vida de Terraform está envuelto en un **Taskfile** (`Taskfile.yml`) para que en clase no tengamos que escribir comandos largos a mano. El state file vive en una **storage account remota** (distinta a la de datos), no en disco, para que sea seguro re-correr el proceso entre máquinas.

## Lo que vamos a crear

| Capa | Recurso | Propósito |
|---|---|---|
| State | `rg-terraform-state-dsrp-modulo4` + storage account + container `tfstate` | Guarda `modulo4.terraform.tfstate` con versionado + soft-delete 30 días |
| **Datos** | **Storage Account `${prefix}data<hex>` + container `dsrp-modulo4`** | **Donde viven `raw/telco_churn.csv` y `models/*.pkl`. Creado por Terraform.** |
| Infra | `rg-${prefix}-trainer` + VNet + Subnet + NSG (SSH 22) + Public IP + NIC + VM B2s | El sandbox donde corre el trainer |
| Auth | Par RSA-4096 + cloud-init | SSH key generada localmente, Docker + systemd + (opcional) timer configurados al primer boot |

Diagrama:

```
                              ┌────────────────────────────────────┐
                              │  rg-terraform-state-dsrp-modulo4   │
                              │  └─ storage account                │
[ tu laptop ] ── terraform ──▶│     └─ container tfstate           │
       │                      │        └─ modulo4.terraform.tfstate│
       │                      └────────────────────────────────────┘
       │
       │ apply
       ▼
┌──────────────────────┐    cloud-init     ┌──────────────────────┐
│  rg-${prefix}-trainer│ ─────────────────▶│  VM B1s Ubuntu 24.04 │
│  VNet + NSG + PIP    │                   │  + Docker            │
└──────────────────────┘                   │  + dsrp-trainer.svc  │
                                           └──────────┬───────────┘
                                                      │ docker pull / push
                                                      ▼
                                           ┌──────────────────────┐
                                           │  ghcr.io + Blob      │
                                           └──────────────────────┘
```

---

## 0. Pre-requisitos (una sola vez)

```bash
# macOS
brew install go-task terraform azure-cli

# Linux
sudo snap install task --classic
sudo apt-get install -y terraform azure-cli

# Verificar
task --version && terraform -version && az version
```

Login en Azure:

```bash
az login
az account set --subscription <SUBSCRIPTION_ID>
```

Necesitas también:
- La **imagen Docker publicada** por la GitHub Action en `ghcr.io/<usuario>/dsrp-modulo4-trainer:latest` (si es privada: un PAT con `read:packages`).

**Ya NO necesitas crear el storage account a mano.** Terraform lo crea y luego `task creds:export` escribe la connection string al `.env` de la raíz para que los notebooks puedan correrse localmente. Ver §1 abajo.

### ¿Por qué `Standard_D2as_v4` en `centralus`? (lección aprendida en vivo)

El default original era `Standard_B2s` en `eastus`. **No funcionó** para la suscripción del curso: Azure devolvió `SkuNotAvailable / Capacity Restrictions` durante `terraform apply`. Al investigar con `az vm list-skus` descubrimos que:

- La suscripción `dsrp-mle-2026` **no ofrece ninguna SKU de la familia BS** (B2s, B2ms) en `eastus`, `eastus2`, `westus2`, `westus3`, ni `centralus`. No es solo capacidad — Azure literalmente no las expone.
- Las familias `Bsv2 / Basv2 / Bpsv2` (la versión moderna de B-series) tienen **quota = 0** en esta suscripción.
- **`DASv4`, `DSv4`, `DDSv4`** sí están disponibles con `quota = 10 vCPU` en `centralus` y `westus3`.

Por eso el nuevo default es **`Standard_D2as_v4` en `centralus`**:

| Propiedad | Standard_B2s (viejo) | Standard_D2as_v4 (nuevo) |
|---|---|---|
| vCPU | 2 | 2 |
| RAM | 4 GiB | **8 GiB** (+4) |
| CPU | Intel burstable | AMD EPYC GP |
| Disponible en esta sub | ❌ | ✅ centralus, westus3 |
| Costo prorrateado | ~$30/mo | ~$70/mo (si dejas la VM 24/7) |
| Con `task destroy` al terminar | ~$0.10 | ~$0.20 |

Si quieres cambiar la región o el tamaño, **siempre corre primero**:

```bash
task vm:check-skus
```

Imprime:
1. Si el SKU configurado está disponible en la región configurada (✅ / 🚫 / ❌).
2. Alternativas de 2 vCPU 4-8 GiB sin restricción en esa región.
3. Tu quota actual por familia.

Eso te ahorra el ~10 min de un `apply` que falla porque la VM no se puede crear.

### ¿Y si tu suscripción es DISTINTA y `D2as_v4` tampoco está?

Mismo flujo:

```bash
# 1. Mira qué tienes disponible en la región actual
task vm:check-skus

# 2. Si nada sirve, prueba otra región — edita location en dsrp-values.tfvars y repite
# 3. Cuando vm:check-skus muestre ✅, haz task apply
```

Regiones que típicamente tienen amplia disponibilidad (en orden de probabilidad): `centralus`, `westus3`, `southcentralus`, `northeurope`, `eastus2`.

---

## 1. Configurar las variables

```bash
cd modulo-4-mlops-y-cloud/terraform
cp dsrp-values.tfvars.example dsrp-values.tfvars
$EDITOR dsrp-values.tfvars
```

Llena al menos:

- `subscription_id` → `az account show --query id -o tsv`
- `image_ref` → reemplaza `CHANGE_ME` por tu usuario de GitHub
- `ghcr_username` / `ghcr_token` → solo si la imagen es privada
- `ssh_allowed_cidr` → `"auto"` por default (Terraform detecta tu IP pública con `https://ifconfig.me/ip` y abre el NSG solo para `<tu_ip>/32`). Si prefieres fijarla a mano, pon `"203.0.113.42/32"`. **No uses** `"0.0.0.0/0"` salvo que sea estrictamente necesario.
- `trainer_schedule` (opcional) → `"hourly"`, `"daily"`, `"*-*-* 03:00:00"`, etc. Vacío = correr solo al primer boot.

> `dsrp-values.tfvars` está en `.gitignore`. **No lo commitees.**

### Auto-detección de tu IP (NSG con `/32` desde IaC)

Por default (`ssh_allowed_cidr = "auto"`) Terraform hace dos cosas:

1. **En `terraform plan/apply`**: el `data "http" "my_ip"` llama a `ifconfig.me`, lee tu IP pública y la combina como `<ip>/32`. Esa es la única IP que el NSG deja entrar por el puerto 22.
2. **En el output `ssh_allowed_cidr_effective`**: te muestra cuál IP terminó autorizada — para confirmar antes de hacer SSH.

¿Qué pasa si te cambia el IP (cambias de red WiFi, reseteas el router, viajas)?

```bash
task vm:nsg-refresh-ip
```

Esto re-detecta tu IP y aplica SOLO el cambio del NSG (`-target=azurerm_network_security_group.nsg`) — no toca la VM ni el storage. Toma ~10 segundos.

Si por alguna razón no quieres dependencia de un servicio externo (CI sin internet hacia ifconfig.me, paranoid mode), fíjala manualmente en tfvars:

```hcl
ssh_allowed_cidr = "203.0.113.42/32"
```

### Manejo de credenciales con esta IaC

El flujo es **una sola fuente de verdad**:

1. Terraform crea el storage account de datos (no tú, no `az`, no el notebook 02).
2. Lee la connection string del Terraform state.
3. Inyecta la connection string al cloud-init de la VM como variable de entorno (`/etc/dsrp/trainer.env`, permisos 600, root-only).
4. Exporta esa misma connection string al `.env` de la raíz del repo con `task creds:export`, para que los **notebooks corran localmente** apuntando al mismo storage.

Ningún secreto vive en archivos versionados:

| Lugar | Contenido | Versionado |
|---|---|---|
| `terraform.tfstate` (remoto en Azure) | Connection string en claro | Sí, en Azure (no en git) |
| `/etc/dsrp/trainer.env` (en la VM) | Connection string en claro, root-only | No |
| `../../.env` (tu laptop) | Connection string en claro | **No** (gitignored) |
| `dsrp-values.tfvars` | **Ya no incluye secretos** — solo subscription id, image ref, schedule | No (gitignored igual) |

Para rotar la key: `az storage account keys renew -g rg-${prefix}-trainer -n <account> --key primary`, luego `terraform refresh` + `task apply` + `task creds:export`.

---

## 2. Crear el backend remoto (state file en Azure)

```bash
task backend:setup
```

Esto hace, idempotentemente:

1. Limpia cualquier `.terraform/` local anterior.
2. Registra el proveedor `Microsoft.Storage` si no está registrado.
3. Crea el resource group `rg-terraform-state-dsrp-modulo4`.
4. Crea una **storage account única** (`tfstatedsrp4XXXXXXXX`) con TLS 1.2 mínimo y blob público deshabilitado.
5. Activa **versionado** y **soft-delete 30 días** en el container — fundamental para no perder el state.
6. Crea el container `tfstate`.
7. Escribe `backend.hcl` con los datos para `terraform init`.

Al final ves:

```
🎉 Backend remoto listo!
💡 Siguiente paso: task init
```

> El nombre de la storage account es aleatorio (sufijo hex 4 bytes). Si lo borras, vuelve a correr `task backend:setup` — pero perderás el state, así que **no lo borres mientras tu infra esté viva**.

---

## 3. Inicializar Terraform contra el backend remoto

```bash
task init
```

Por dentro corre:

```
terraform init -backend-config=backend.hcl -input=false
```

Esto descarga los providers (`azurerm`, `tls`, `local`) y **conecta** el state local con el storage remoto. A partir de aquí, cada `apply` actualiza el `.tfstate` que vive en Azure.

Verifica:

```bash
task validate
task fmt
```

---

## 4. Plan y apply

```bash
task plan
```

Genera `tfplan`. Revisa la salida — debes ver ~15 recursos a crear (RG, VNet, Subnet, NSG, PIP, NIC, NSG-NIC assoc, VM, OS disk, **storage account + container de datos**, random_id, llaves TLS, archivos locales).

```bash
task apply
```

Aplica `tfplan` si existe, o corre `apply` con tfvars directamente. Tarda **~3–5 minutos**: la mayor parte es Azure aprovisionando la VM.

Outputs útiles al terminar:

```bash
task outputs
```

```
public_ip               = "20.42.x.x"
ssh_command             = "ssh -i ssh/dsrpm4-trainer.pem azureuser@20.42.x.x"
image_ref               = "ghcr.io/<user>/dsrp-modulo4-trainer:latest"
storage_account_name    = "dsrpm4dataa1b2c3d4"
storage_container_name  = "dsrp-modulo4"
trainer_schedule        = ""
tail_trainer_logs       = "sudo journalctl -u dsrp-trainer.service -f"
```

Y para correr los notebooks localmente contra ese mismo storage:

```bash
task creds:export        # escribe AZURE_STORAGE_* en ../../.env
```

### Atajo: `task deploy`

Si quieres hacer todo de un solo golpe — backend + init + apply + export de creds:

```bash
task deploy
```

Te pide confirmación una vez y deja la infra arriba más el `.env` listo para los notebooks.

---

## 5. Verificar que el trainer entrenó

Cloud-init tarda **~2 minutos** después de que la VM está "Running": instala Docker, hace `pull` de la imagen y corre el container como `systemd oneshot`.

```bash
task logs
```

Te conecta por SSH y sigue los logs del servicio. Cada corrida del trainer imprime secciones bien marcadas (RUNTIME, DESCARGA, DATASET, PREPROCESAMIENTO, PIPELINE, ENTRENAMIENTO, MÉTRICAS, UPLOAD, RESUMEN). Algo así (truncado):

```
[train] ─────────────
[train]  RUNTIME
[train] ─────────────
[train] run_id          = 20261105T093020Z
[train] python          = 3.12.7 (CPython)
[train] sklearn         = 1.5.2
[train] container       = azure://dsrp-modulo4
[train] rss_inicial_mb  = 92.3

[train] ─────────────
[train]  DESCARGA DATOS
[train] ─────────────
[train] GET azure://dsrp-modulo4/raw/telco_churn.csv
[train] descargado      : 977,501 bytes en 0.42s (2.2 MiB/s)
[train] parseado        : 7,043 filas × 21 columnas

[train] ─────────────
[train]  ENTRENAMIENTO
[train] ─────────────
[train] X_train         : (5625, 19)
[train] X_test          : (1407, 19)
[train] features OHE    : 45
[train] fit duration_s  : 0.31
[train] rss_post_fit_mb : 187.5

[train] ─────────────
[train]  MÉTRICAS
[train] ─────────────
[train] train accuracy  : 0.8123
[train] test  accuracy  : 0.8101
[train] test  roc_auc   : 0.8467
[train] test  precision : 0.6710
[train] test  recall    : 0.5481
[train] test  f1        : 0.6034
[train] overfit gap     : +0.0022
[train] confusion matrix (rows=actual, cols=pred):
[train]               pred_no_churn  pred_churn
[train]   no_churn           945         88
[train]   churn              169        205

[train] ─────────────
[train]  RESUMEN
[train] ─────────────
[train] OK              : modelo disponible en https://dsrpm4data....blob.core.windows.net/...
[train] duración_total_s: 4.21
```

`Ctrl-C` para salir del `journalctl -f`. Para greps rápidos cuando hay muchas corridas:

```bash
sudo journalctl -u dsrp-trainer.service | grep -E "(run_id|test  accuracy|test  roc_auc|duración_total_s)"
```

### Anatomía de los logs

Cada sección responde a una pregunta operacional concreta:

| Sección | ¿Qué confirma? |
|---|---|
| RUNTIME            | "¿estoy corriendo la versión correcta de Python/sklearn?" — útil cuando un `.pkl` falla al cargarse en otra máquina. |
| DESCARGA DATOS     | "¿el blob bajó? ¿en cuánto tiempo?" — ancho de banda VM ↔ Azure Storage. |
| DATASET            | "¿el CSV es el que esperaba?" — shape, nulos, balance de clases. |
| PREPROCESAMIENTO   | "¿cuántas filas tuve que descartar?" — drift / calidad de datos. |
| PIPELINE           | "¿qué columnas son numéricas vs categóricas?" — detecta cambios de esquema. |
| ENTRENAMIENTO      | "¿cuánto tardó el fit? ¿cuánta RAM uso?" — capacity planning de la VM. |
| MÉTRICAS           | "¿es mejor o peor que la corrida anterior?" — incluye overfit gap. |
| UPLOAD             | "¿el .pkl quedó arriba?" — tamaño + tiempo + URL. |
| RESUMEN            | duración total + RSS final. |

Y desde tu laptop, confirma que el `.pkl` quedó arriba:

```bash
az storage blob list \
  --container-name dsrp-modulo4 \
  --prefix models/ \
  --connection-string "$AZURE_STORAGE_CONNECTION_STRING" \
  --output table
```

---

## 6. Re-correr el trainer sin destruir la VM

```bash
task trainer:rerun
```

Reinicia el `dsrp-trainer.service` (es `Type=oneshot`) y muestra las últimas 50 líneas.

También puedes hacerlo manualmente:

```bash
task ssh
sudo systemctl start dsrp-trainer.service
sudo journalctl -u dsrp-trainer.service -f
```

### Explorar el contenedor Docker en la VM (SSH guiado)

`task ssh` abre una sesión interactiva contra la VM. Antes de tirarte al shell, imprime la IP, el CIDR autorizado por el NSG, y un cheat-sheet de comandos para inspeccionar Docker. Lo más útil cuando entras:

```bash
# ¿qué contenedores hay? (el trainer es oneshot, así que normalmente "Exited (0)")
docker ps -a

# imágenes descargadas (el image_ref que pediste + capas base)
docker images

# logs del último run del trainer (si todavía no se borró el contenedor)
docker logs dsrp-trainer

# explorar la imagen INTERACTIVAMENTE — abre un bash dentro de ella, ÚTIL para debug
docker run --rm -it \
  --env-file /etc/dsrp/trainer.env \
  --entrypoint bash \
  ghcr.io/<tu-usuario>/dsrp-modulo4-trainer:latest

# ya dentro del container: explora /app, corre train.py paso a paso, etc.
ls /app
python -c "import sklearn; print(sklearn.__version__)"
```

Si no quieres SSHear y solo quieres ejecutar uno de estos rápido, hay shortcuts:

| Task | Qué hace |
|---|---|
| `task vm:docker-ps`       | `docker ps -a` remoto en una línea |
| `task vm:docker-images`   | `docker images` remoto |
| `task vm:docker-inspect`  | `docker image inspect <image_ref>` — entrypoint, env, labels |
| `task vm:docker-shell`    | abre bash dentro de la imagen del trainer (con `--env-file /etc/dsrp/trainer.env`) |

Estos comandos son *exactamente* lo que harías a mano por SSH; solo te ahorran teclear la IP/key cada vez.

> El `--env-file /etc/dsrp/trainer.env` es importante: ahí vive la connection string que cloud-init dejó (con permisos 0600, solo root). Si abres el bash sin eso, las llamadas a Azure fallan.

### Correr el trainer periódicamente (cron-like)

La VM es **persistente** (vive hasta `task destroy`). Para que el trainer se dispare solo cada X tiempo no usamos crontab — el cloud-init ya instala un **systemd timer** (`dsrp-trainer.timer`) que apunta al mismo `.service` oneshot.

Dos formas de activarlo:

**A. Desde el primer apply (declarativo, recomendado):**

```hcl
# dsrp-values.tfvars
trainer_schedule = "*-*-* 03:00:00"   # todos los días 03:00 UTC
```

Luego `task apply` (si recreas la VM) o `task apply` + `terraform taint azurerm_linux_virtual_machine.vm` para forzar re-correr cloud-init.

**B. En vivo, sin recrear la VM:**

```bash
task trainer:schedule:on    # habilita el timer con el OnCalendar que ya quedó
task trainer:status         # muestra service + timer + próximos disparos
task trainer:schedule:off   # apaga el timer
```

Sintaxis de `OnCalendar` (usa `systemd.time(7)`):

| Expresión | Cuándo dispara |
|---|---|
| `hourly` | cada hora en punto |
| `daily` | cada día a las 00:00 UTC |
| `*-*-* 03:00:00` | todos los días a las 03:00 UTC |
| `Mon..Fri 08:00:00` | lunes a viernes 08:00 UTC |
| `*:0/15` | cada 15 minutos |

`Persistent=true` está activado: si la VM estaba apagada cuando tocaba un firing, se ejecuta una vez en cuanto vuelve. Para algo más complejo (DAGs, retries, observabilidad) tendrías que graduarte a Azure Container Apps Jobs o Airflow — pero para una clase, esto sobra.

---

## 7. Destruir

Cuando termines la clase, **destruye todo** para no acumular costos:

```bash
task destroy
```

Esto borra la VM y todos los recursos del RG `rg-${prefix}-trainer` — **incluido el Storage Account de datos** (porque ahora es Terraform quien lo crea). Si quieres conservar los blobs entre sesiones, antes del destroy haz:

```bash
az storage blob download-batch \
  -d ./backup-blobs \
  -s "$AZURE_STORAGE_CONTAINER" \
  --connection-string "$AZURE_STORAGE_CONNECTION_STRING"
```

**El state remoto NO se borra.** Te deja el `.tfstate` histórico, recuperable por versión.

Si quieres limpiar también el state:

```bash
task backend:destroy
```

Y para borrar artefactos locales (`.terraform/`, `tfplan`, `ssh/*`):

```bash
task clean
```

---

## Resumen de tasks

| Task | Cuándo usarlo |
|---|---|
| `task deploy` | **De cero a infra arriba** — backend + init + apply + creds:export |
| `task backend:setup` | **Una vez por proyecto** — crea state account |
| `task init` | Después de `backend:setup` o al cambiar providers |
| `task fmt` / `task validate` | Antes de commits / PRs |
| `task plan` | Para revisar cambios antes de aplicarlos |
| `task apply` | Crear/actualizar la infra |
| `task outputs` | Ver IP, comando SSH, etc. |
| `task creds:export` | Volcar la connection string al `.env` de la raíz (para notebooks locales) |
| `task ssh` | Conectarse a la VM (imprime cheat-sheet de exploración) |
| `task vm:check-skus` | **Pre-flight**: verifica si el `vm_size` configurado está disponible en la región para tu suscripción (úsalo ANTES de `task apply`) |
| `task vm:nsg-refresh-ip` | Re-aplica el NSG con tu IP pública actual (si te cambia de red) |
| `task vm:docker-ps` / `vm:docker-images` / `vm:docker-inspect` / `vm:docker-shell` | Inspecciona Docker en la VM sin abrir sesión interactiva |
| `task logs` | Tail de logs del trainer |
| `task trainer:rerun` | Re-disparar el trainer sin destruir la VM |
| `task trainer:status` | Estado de `dsrp-trainer.service` + `.timer` + próximos disparos |
| `task trainer:schedule:on` / `off` | Encender / apagar el systemd timer en vivo |
| `task destroy` | Borrar la VM **y el storage de datos** al terminar la clase |
| `task backend:destroy` | Borrar también el state remoto |
| `task clean` | Limpiar artefactos locales |

Para ver el listado en cualquier momento: `task` (sin argumentos).

---

## Costos aproximados

| Recurso | Costo estimado | Free tier 12 meses |
|---|---|---|
| Storage account del state (LRS) | < $0.10/mes (KB de tfstate) | ❌ pero es trivial |
| Storage account de datos (LRS) | < $0.10/mes (1 CSV + algunos pkl) | ❌ pero trivial |
| VM Standard_B2s, Linux | ~$30/mes prorrateado | ❌ |
| VM Standard_B1s (si bajas) | ~$8/mes | ✅ 750 h/mes |
| Public IP estándar (estática) | ~$3/mes | ❌ |
| OS disk 30 GB | ~$1.50/mes | ✅ parcial |

**Con `task destroy` al final de cada sesión, el costo mensual real ronda los $0.10–$2.**

---

## Troubleshooting

**"Backend reinitialization required."** — Pasa si tocas el `backend "azurerm" {}` o si `backend.hcl` cambió. Corre `task init` de nuevo.

**"Error acquiring the state lock."** — Otro `terraform apply` está corriendo, o uno previo crasheó y dejó el lock. Espera, o fuerza `terraform force-unlock <LOCK_ID>` (el ID sale en el error).

**El trainer no aparece en `journalctl`.** — Cloud-init aún no terminó. Espera 2 min más. Para inspeccionar: `sudo cat /var/log/cloud-init-output.log`.

**Cloud-init fallido con `docker: command not found`.** — Reinicia la VM con `task ssh` + `sudo reboot`. El servicio reintentará al levantar.

**`docker pull` da `unauthorized`.** — La imagen es privada y faltan `ghcr_username` + `ghcr_token` en `dsrp-values.tfvars`. Rellénalos y `task apply` re-ejecuta cloud-init si recreas la VM (`terraform taint azurerm_linux_virtual_machine.vm`).

**`ssh: connect to host … Connection timed out`.** — Casi siempre es que tu IP cambió (te cambiaste de WiFi, reiniciaste el router) y el NSG ya no te deja entrar. Solución: `task vm:nsg-refresh-ip`. Verifica con `terraform output -raw ssh_allowed_cidr_effective` que efectivamente sea tu IP actual (`curl ifconfig.me`).

**`Error: Get "https://ifconfig.me/ip": …`** durante `terraform plan/apply`. — El servicio externo está caído o no tienes salida a internet. Fíjate la IP a mano en tfvars: `ssh_allowed_cidr = "$(curl -s ifconfig.me)/32"`.

**`SkuNotAvailable: The requested VM size … is currently not available in location 'xxx'`** durante `terraform apply`. — Tu suscripción no tiene esa SKU disponible en esa región. Corre `task vm:check-skus` para ver alternativas, edita `vm_size` (o `location`) en `dsrp-values.tfvars`, y vuelve a aplicar. La regla de pulgar para este curso: **`Standard_D2as_v4` en `centralus`** funciona. B-series (B2s, B2ms) NO está disponible en esta suscripción en ninguna región probada — no la uses sin verificar primero.
