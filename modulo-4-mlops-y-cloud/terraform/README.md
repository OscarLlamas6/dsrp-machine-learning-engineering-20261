# Terraform — VM Azure con state remoto (paso a paso)

Este es el laboratorio del módulo 4. Vamos a provisionar en Azure una VM `Standard_B1s` que descargue, vía Docker, la imagen del trainer construida por la GitHub Action y la ejecute contra el contenedor de Blob Storage del notebook 02.

Todo el ciclo de vida de Terraform está envuelto en un **Taskfile** (`Taskfile.yml`) para que en clase no tengamos que escribir comandos largos a mano. El state file vive en una **storage account remota**, no en disco, para que sea seguro re-correr el proceso entre máquinas.

## Lo que vamos a crear

| Capa | Recurso | Propósito |
|---|---|---|
| State | `rg-terraform-state-dsrp-modulo4` + storage account + container `tfstate` | Guarda `modulo4.terraform.tfstate` con versionado + soft-delete 30 días |
| Infra | `rg-${prefix}-trainer` + VNet + Subnet + NSG (SSH 22) + Public IP + NIC + VM B1s | El sandbox donde corre el trainer |
| Auth | Par RSA-4096 + cloud-init | SSH key generada localmente, Docker + systemd configurados al primer boot |

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
- La **connection string** de la Storage Account del notebook 02.
- La **imagen Docker publicada** por la GitHub Action en `ghcr.io/<usuario>/dsrp-modulo4-trainer:latest` (si es privada: un PAT con `read:packages`).

---

## 1. Configurar las variables

```bash
cd modulo-4-mlops-y-cloud/terraform
cp dsrp-values.tfvars.example dsrp-values.tfvars
$EDITOR dsrp-values.tfvars
```

Llena al menos:

- `subscription_id` → `az account show --query id -o tsv`
- `azure_storage_connection_string` → la del notebook 02
- `image_ref` → reemplaza `CHANGE_ME` por tu usuario de GitHub
- `ghcr_username` / `ghcr_token` → solo si la imagen es privada
- `ssh_allowed_cidr` → idealmente tu IP (`$(curl -s ifconfig.me)/32`)

> `dsrp-values.tfvars` está en `.gitignore`. **No lo commitees.**

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

Genera `tfplan`. Revisa la salida — debes ver ~13 recursos a crear (RG, VNet, Subnet, NSG, PIP, NIC, NSG-NIC assoc, VM, OS disk, llaves TLS, archivos locales).

```bash
task apply
```

Aplica `tfplan` si existe, o corre `apply` con tfvars directamente. Tarda **~3–5 minutos**: la mayor parte es Azure aprovisionando la VM.

Outputs útiles al terminar:

```bash
task outputs
```

```
public_ip        = "20.42.x.x"
ssh_command      = "ssh -i ssh/dsrpm4-trainer.pem azureuser@20.42.x.x"
image_ref        = "ghcr.io/<user>/dsrp-modulo4-trainer:latest"
tail_trainer_logs = "sudo journalctl -u dsrp-trainer.service -f"
```

---

## 5. Verificar que el trainer entrenó

Cloud-init tarda **~2 minutos** después de que la VM está "Running": instala Docker, hace `pull` de la imagen y corre el container como `systemd oneshot`.

```bash
task logs
```

Te conecta por SSH y sigue los logs del servicio. Deberías ver:

```
[train] descargando blob azure://dsrp-modulo4/raw/telco_churn.csv
[train] shape descargado: (7043, 21)
[train] entrenando LogisticRegression con preprocesamiento...
[train] métricas: accuracy=0.8094  roc_auc=0.8467
[train] subiendo modelo a azure://dsrp-modulo4/models/telco_churn_logreg.pkl
[train] OK — modelo disponible en https://...
[train] tiempo total: 23.4s
```

`Ctrl-C` para salir del `journalctl -f`.

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

---

## 7. Destruir

Cuando termines la clase, **destruye todo** para no acumular costos:

```bash
task destroy
```

Esto borra la VM y todos los recursos del RG `rg-${prefix}-trainer`. Te pide confirmación.

**El state remoto y la Storage Account de Blob Storage NO se borran.** Eso te deja:
- El `.tfstate` histórico (puedes recuperar cualquier versión gracias al versionado).
- Los blobs del notebook 02 (`raw/`, `models/`) intactos.

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
| `task backend:setup` | **Una vez por proyecto** — crea state account |
| `task init` | Después de `backend:setup` o al cambiar providers |
| `task fmt` / `task validate` | Antes de commits / PRs |
| `task plan` | Para revisar cambios antes de aplicarlos |
| `task apply` | Crear/actualizar la infra |
| `task outputs` | Ver IP, comando SSH, etc. |
| `task ssh` | Conectarse a la VM |
| `task logs` | Tail de logs del trainer |
| `task trainer:rerun` | Re-disparar el trainer sin destruir la VM |
| `task destroy` | Borrar la VM al terminar la clase |
| `task backend:destroy` | Borrar también el state remoto |
| `task clean` | Limpiar artefactos locales |

Para ver el listado en cualquier momento: `task` (sin argumentos).

---

## Costos aproximados

| Recurso | Costo estimado | Free tier 12 meses |
|---|---|---|
| Storage account del state (LRS) | < $0.10/mes (KB de tfstate) | ❌ pero es trivial |
| VM Standard_B1s, Linux | ~$8/mes prorrateado | ✅ 750 h/mes |
| Public IP estándar (estática) | ~$3/mes | ❌ |
| OS disk 30 GB | ~$1.50/mes | ✅ parcial |

**Con `task destroy` al final de cada sesión, el costo mensual real ronda los $0.10–$1.**

---

## Troubleshooting

**"Backend reinitialization required."** — Pasa si tocas el `backend "azurerm" {}` o si `backend.hcl` cambió. Corre `task init` de nuevo.

**"Error acquiring the state lock."** — Otro `terraform apply` está corriendo, o uno previo crasheó y dejó el lock. Espera, o fuerza `terraform force-unlock <LOCK_ID>` (el ID sale en el error).

**El trainer no aparece en `journalctl`.** — Cloud-init aún no terminó. Espera 2 min más. Para inspeccionar: `sudo cat /var/log/cloud-init-output.log`.

**Cloud-init fallido con `docker: command not found`.** — Reinicia la VM con `task ssh` + `sudo reboot`. El servicio reintentará al levantar.

**`docker pull` da `unauthorized`.** — La imagen es privada y faltan `ghcr_username` + `ghcr_token` en `dsrp-values.tfvars`. Rellénalos y `task apply` re-ejecuta cloud-init si recreas la VM (`terraform taint azurerm_linux_virtual_machine.vm`).
