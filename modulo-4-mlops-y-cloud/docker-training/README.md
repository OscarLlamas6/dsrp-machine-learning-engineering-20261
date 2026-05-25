# Docker training — Telco Churn

Imagen Docker que:

1. Descarga `raw/telco_churn.csv` desde Azure Blob Storage.
2. Entrena un `LogisticRegression` con preprocesamiento (`StandardScaler` + `OneHotEncoder`).
3. Imprime accuracy y ROC-AUC.
4. Sube `models/telco_churn_logreg.pkl` al mismo contenedor.

## Pre-requisitos

- Haber corrido el notebook `02_azure_blob_storage_sdk.ipynb` (deja el CSV en `raw/telco_churn.csv`).
- Tener la variable `AZURE_STORAGE_CONNECTION_STRING` en un `.env` (o en el environment).

## Build local

Desde la raíz del repo:

```bash
docker build -t dsrp-modulo4-trainer:local -f modulo-4-mlops-y-cloud/docker-training/Dockerfile modulo-4-mlops-y-cloud/docker-training
```

## Run local

```bash
docker run --rm \
  --env-file .env \
  -e AZURE_STORAGE_CONTAINER=dsrp-modulo4 \
  dsrp-modulo4-trainer:local
```

Salida esperada (truncada):

```
[train] descargando blob azure://dsrp-modulo4/raw/telco_churn.csv
[train] shape descargado: (7043, 21)
[train] entrenando LogisticRegression con preprocesamiento...
[train] métricas: accuracy=0.8094  roc_auc=0.8467
[train] subiendo modelo a azure://dsrp-modulo4/models/telco_churn_logreg.pkl
[train] OK — modelo disponible en https://...
```

## Variables de entorno

| Variable | Default | Propósito |
|---|---|---|
| `AZURE_STORAGE_CONNECTION_STRING` | _(requerida)_ | Auth contra Blob Storage |
| `AZURE_STORAGE_CONTAINER` | `dsrp-modulo4` | Contenedor de input/output |
| `INPUT_BLOB` | `raw/telco_churn.csv` | Blob a descargar como dataset |
| `OUTPUT_BLOB` | `models/telco_churn_logreg.pkl` | Destino del `.pkl` |

## Imagen publicada en GHCR

La GitHub Action `.github/workflows/build-modulo4-image.yml` publica esta imagen como:

```
ghcr.io/<tu-usuario>/dsrp-modulo4-trainer:latest
ghcr.io/<tu-usuario>/dsrp-modulo4-trainer:<sha-corto>
```

Para correrla desde la imagen del registry (en cualquier máquina con Docker):

```bash
docker run --rm \
  --env-file .env \
  ghcr.io/<tu-usuario>/dsrp-modulo4-trainer:latest
```

Eso es justamente lo que va a hacer la VM provisionada con Terraform en `../terraform/`.
