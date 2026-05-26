# Módulo 4 — MLOps y Herramientas Cloud

**Profesor:** Miguel Arquez
**DSRP Machine Learning Engineering**

Este módulo cubre cómo llevar un modelo de ML del notebook a la nube: empaquetado en Docker, almacenamiento de artefactos en object storage, CI/CD con GitHub Actions e infraestructura como código con Terraform.

## Contenido

| # | Archivo / Carpeta | Tema |
|---|---|---|
| 1 | [01_introduccion_mlops_y_cloud.ipynb](01_introduccion_mlops_y_cloud.ipynb) | Qué es MLOps, ciclo de vida de un modelo en producción, mapa de herramientas cloud. |
| 2 | [02_azure_blob_storage_sdk.ipynb](02_azure_blob_storage_sdk.ipynb) | Azure Blob Storage con `azure-storage-blob`: subir, descargar y listar blobs sobre el dataset Telco. |
| 3 | [docker-training/](docker-training/) | Imagen Docker que entrena un modelo sobre Telco Churn y sube el `.pkl` a Azure Blob Storage. |
| 4 | [../.github/workflows/build-modulo4-image.yml](../.github/workflows/build-modulo4-image.yml) | GitHub Action que construye la imagen del paso 3 y la publica en GitHub Container Registry (`ghcr.io`). |
| 5 | [terraform/](terraform/) | Terraform que provisiona una VM `Standard_B1s` en Azure (state remoto en Azure Storage), abre SSH, instala Docker y ejecuta el contenedor del paso 3 contra el blob del paso 2. Envuelto en un **Taskfile** (`task backend:setup`, `task init`, `task plan`, `task apply`, `task destroy`, …). |
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
│ Azure Blob      │◀── push modelo_telco.pkl ────│ VM Azure B1s     │
│ Storage         │                              │ (Terraform)      │
│ container=models│──── pull Telco.csv ─────────▶│ entrena en cloud │
└─────────────────┘                              └──────────────────┘
```

## Requisitos extra (encima de los del repo raíz)

- **Cuenta de Azure** con suscripción activa (la capa gratuita basta para `Standard_B1s` + Blob Storage hot).
- **Azure CLI** (`brew install azure-cli` en macOS, o ver https://learn.microsoft.com/cli/azure/install-azure-cli).
- **Docker Desktop** corriendo localmente.
- **Terraform ≥ 1.6** (`brew install terraform` o https://developer.hashicorp.com/terraform/install).
- **go-task** (`brew install go-task`) — orquesta el ciclo Terraform vía [terraform/Taskfile.yml](terraform/Taskfile.yml).
- **GitHub CLI** (opcional, `gh auth login`) para usar `ghcr.io` sin tokens manuales.

Variables de entorno usadas a lo largo del módulo (añádelas a tu `.env` en la raíz):

```bash
AZURE_STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=...;AccountKey=...;EndpointSuffix=core.windows.net"
AZURE_STORAGE_CONTAINER="dsrp-modulo4"
AZURE_SUBSCRIPTION_ID="..."
```

## Orden recomendado

1. Lee `01_introduccion_mlops_y_cloud.ipynb` para el contexto.
2. Crea el container de Blob Storage con `02_azure_blob_storage_sdk.ipynb` y sube `WA_Fn-UseC_-Telco-Customer-Churn.csv`.
3. Construye localmente la imagen Docker (`docker-training/`) y verifica que entrena y sube el `.pkl`.
4. Empuja un cambio cualquiera al repo y observa cómo GitHub Actions reconstruye y publica la imagen.
5. Aplica el Terraform usando el Taskfile:
   ```bash
   cd modulo-4-mlops-y-cloud/terraform
   cp dsrp-values.tfvars.example dsrp-values.tfvars   # edítalo
   task backend:setup    # crea state account en Azure (una sola vez)
   task init             # terraform init con backend remoto
   task plan             # revisa
   task apply            # provisiona VM + corre el trainer en cloud
   task logs             # tail journalctl del trainer
   task destroy          # al terminar la clase, derriba todo
   ```
   El paso a paso completo está en [terraform/README.md](terraform/README.md).
