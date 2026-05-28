# Módulo 4 — MLOps y Herramientas Cloud

**Profesor:** Miguel Arquez
**DSRP Machine Learning Engineering**

Este módulo cubre cómo llevar un modelo de ML del notebook a la nube: empaquetado en Docker, almacenamiento de artefactos en object storage, CI/CD con GitHub Actions e infraestructura como código con Terraform.

## Contenido

| # | Archivo / Carpeta | Tema |
|---|---|---|
| 1 | [01_introduccion_mlops_y_cloud.ipynb](01_introduccion_mlops_y_cloud.ipynb) | Qué es MLOps, ciclo de vida de un modelo en producción, mapa de herramientas cloud. |
| 2 | [02_azure_blob_storage_sdk.ipynb](02_azure_blob_storage_sdk.ipynb) | Azure Blob Storage con `azure-storage-blob`: subir, descargar y listar blobs sobre el dataset Telco. |
| 3 | [03_entrenamiento_local.ipynb](03_entrenamiento_local.ipynb) | El mismo pipeline que el contenedor Docker, pero corriendo local con `uv` — para entender qué hace `train.py` paso a paso. |
| 4 | [docker-training/](docker-training/) | Imagen Docker que entrena un modelo sobre Telco Churn y sube el `.pkl` a Azure Blob Storage. Incluye `Taskfile.yml` para `build` / `run` local. |
| 5 | [../.github/workflows/build-modulo4-image.yml](../.github/workflows/build-modulo4-image.yml) | GitHub Action que construye la imagen del paso 4 y la publica en GitHub Container Registry (`ghcr.io`). |
| 6 | [terraform/](terraform/) | Terraform que provisiona el Storage Account de datos + una VM `Standard_B2s` en Azure (state remoto), abre SSH, instala Docker y ejecuta el contenedor del paso 4. Opcionalmente programa la corrida con un **systemd timer** (`trainer_schedule`). Envuelto en un **Taskfile** (`task deploy`, `task creds:export`, `task trainer:schedule:on`, …). |
| ⭐ | [skills/ds-ml-repo-init/](skills/ds-ml-repo-init/) | **Skill de Claude Code** para bootstrappear un repositorio de Data Science / ML siguiendo buenas prácticas (estructura, `pyproject.toml`, `.gitignore`, CI, Docker base). |

## El pipeline completo

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│  GitHub repo    │───▶│ GitHub Actions   │───▶│ ghcr.io/<user>/...  │
│ (módulo 4)      │    │ build-modulo4    │    │ imagen Docker       │
└─────────────────┘    └──────────────────┘    └──────────┬──────────┘
                                                          │ docker pull
                                                          ▼
┌─────────────────┐                              ┌──────────────────┐
│ Azure Blob      │◀── push modelo_telco.pkl ────│ VM Azure B2s     │
│ Storage (creado │                              │ (Terraform +     │
│ por Terraform)  │──── pull Telco.csv ─────────▶│ systemd timer)   │
└─────────────────┘                              └──────────────────┘
        ▲
        │ creds:export → .env
        │
┌─────────────────┐
│ Notebooks       │  03_entrenamiento_local.ipynb usa el MISMO
│ locales (uv)    │  storage account → reproduce lo que hace el container
└─────────────────┘
```

## Requisitos extra (encima de los del repo raíz)

- **Cuenta de Azure** con suscripción activa (la capa gratuita basta para `Standard_B1s` + Blob Storage hot).
- **Azure CLI** (`brew install azure-cli` en macOS, o ver https://learn.microsoft.com/cli/azure/install-azure-cli).
- **Docker Desktop** corriendo localmente.
- **Terraform ≥ 1.6** (`brew install terraform` o https://developer.hashicorp.com/terraform/install).
- **go-task** (`brew install go-task`) — orquesta el ciclo Terraform vía [terraform/Taskfile.yml](terraform/Taskfile.yml).
- **GitHub CLI** (opcional, `gh auth login`) para usar `ghcr.io` sin tokens manuales.

Variables de entorno usadas a lo largo del módulo (en tu `.env` de la raíz):

```bash
AZURE_STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=...;AccountKey=...;EndpointSuffix=core.windows.net"
AZURE_STORAGE_ACCOUNT="dsrpm4data<hex>"
AZURE_STORAGE_CONTAINER="dsrp-modulo4"
AZURE_SUBSCRIPTION_ID="..."
```

> **No las escribas a mano si vas por la ruta IaC.** Después de `task deploy` corre `task creds:export` y Terraform las vuelca al `.env` por ti.

## Orden recomendado

### Ruta A — empezar por la nube (más rápido, todo en un solo `task`)

```bash
cd modulo-4-mlops-y-cloud/terraform
cp dsrp-values.tfvars.example dsrp-values.tfvars   # edita: subscription_id, image_ref, ssh_allowed_cidr
task deploy           # backend:setup → init → apply → creds:export
```

Eso te deja:
- Storage account + container en Azure.
- VM B2s corriendo el trainer una vez (cloud-init).
- `.env` de la raíz con las credenciales para que los notebooks corran localmente.

Después:

```bash
cd ../..
uv run jupyter lab                # corre el 02 y el 03 con el storage ya creado
cd modulo-4-mlops-y-cloud/terraform
task logs                         # tail del trainer en cloud (secciones RUNTIME, DATASET, MÉTRICAS, …)
task ssh                          # SSH a la VM con cheat-sheet de comandos Docker
task vm:docker-shell              # abre bash DENTRO de la imagen del trainer (para debug)
task vm:nsg-refresh-ip            # si te cambia el IP y SSH deja de funcionar
task trainer:schedule:on          # opcional: que se ejecute cada hora con systemd timer
task destroy                      # al terminar la clase
```

### Seguridad por default

- **NSG con tu IP/32**: por default `ssh_allowed_cidr = "auto"` → Terraform detecta tu IP pública en cada apply y restringe el puerto 22 a `<tu_ip>/32`. Nadie más en internet puede tocar la VM.
- **Storage account privado**: `allow_nested_items_to_be_public = false` y el container es `private`. La única forma de leer los blobs es con la connection string (que Terraform inyecta en cloud-init con permisos `0600` en `/etc/dsrp/trainer.env`).
- **`.env` y `dsrp-values.tfvars` gitignored**: ningún secreto vive en git.

### Ruta B — paso a paso (más didáctico)

1. Lee `01_introduccion_mlops_y_cloud.ipynb` para el contexto.
2. Provisiona Storage Account con Terraform (`task deploy` o solo `task apply` si ya hiciste backend:setup) **o** créalo a mano con `az` (las instrucciones aún viven en el notebook 02).
3. `task creds:export` para tener la connection string en `.env`.
4. Corre `02_azure_blob_storage_sdk.ipynb` para subir el CSV y entender el SDK.
5. Corre `03_entrenamiento_local.ipynb` para entrenar el modelo en tu laptop apuntando al mismo storage.
6. Construye y corre la imagen Docker localmente:
   ```bash
   cd modulo-4-mlops-y-cloud/docker-training
   task build-run     # build + docker run con --env-file ../../.env
   ```
7. Empuja un cambio al repo y observa cómo GitHub Actions reconstruye y publica la imagen.
8. La misma VM aprovisionada en el paso 2 ya está corriendo `ghcr.io/<user>/dsrp-modulo4-trainer:latest`. Para forzar otra corrida: `task trainer:rerun`. Para programarla: `task trainer:schedule:on` (o `trainer_schedule` en tfvars).
9. `task destroy` al terminar.

El paso a paso completo de Terraform está en [terraform/README.md](terraform/README.md).
