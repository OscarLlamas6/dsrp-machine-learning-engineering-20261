# Docker training — Telco Churn

Imagen Docker que:

1. Descarga `raw/telco_churn.csv` desde Azure Blob Storage.
2. Entrena un `LogisticRegression` con preprocesamiento (`StandardScaler` + `OneHotEncoder`).
3. Imprime accuracy y ROC-AUC.
4. Sube `models/telco_churn_logreg.pkl` al mismo contenedor.

## Pre-requisitos

- Docker Desktop corriendo.
- `AZURE_STORAGE_CONNECTION_STRING` en el `.env` de la raíz del repo. Dos formas:
  - **Vía Terraform (recomendada):** `cd ../terraform && task deploy` (la primera vez) o `task creds:export` (si ya existe la infra). Esto crea el storage account *y* escribe el `.env`.
  - **A mano con Azure CLI:** sigue las instrucciones del notebook 02 (`az storage account create …` + `az storage account show-connection-string`).
- Haber corrido `02_azure_blob_storage_sdk.ipynb` (o `03_entrenamiento_local.ipynb` hasta la celda de upload) para dejar el CSV en `raw/telco_churn.csv` dentro del container.

## Build + run local (la forma corta)

Hay un `Taskfile.yml` en esta carpeta:

```bash
cd modulo-4-mlops-y-cloud/docker-training
task build-run    # = docker build + docker run --env-file ../../.env
task run          # solo correr (no rebuild)
task shell        # entrar al container con bash
task clean        # borrar la imagen
```

## Build + run local (la forma manual)

Desde la raíz del repo:

```bash
docker build -t dsrp-modulo4-trainer:local -f modulo-4-mlops-y-cloud/docker-training/Dockerfile modulo-4-mlops-y-cloud/docker-training

docker run --rm \
  --env-file .env \
  -e AZURE_STORAGE_CONTAINER=dsrp-modulo4 \
  dsrp-modulo4-trainer:local
```

Salida esperada (secciones marcadas con barras `─────────`):

```
[train] ─── RUNTIME ───
[train] run_id          = 20261105T093020Z
[train] python          = 3.12.7 (CPython)
[train] sklearn         = 1.5.2
[train] container       = azure://dsrp-modulo4
[train] rss_inicial_mb  = 92.3

[train] ─── DESCARGA DATOS ───
[train] descargado      : 977,501 bytes en 0.42s (2.2 MiB/s)
[train] parseado        : 7,043 filas × 21 columnas

[train] ─── DATASET ───
[train] target (Churn):
[train]   - No     5,174  (73.5%)
[train]   - Yes    1,869  (26.5%)

[train] ─── ENTRENAMIENTO ───
[train] fit duration_s  : 0.31
[train] rss_post_fit_mb : 187.5

[train] ─── MÉTRICAS ───
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

[train] ─── RESUMEN ───
[train] duración_total_s: 4.21
```

Esa misma salida es la que ves con `task logs` cuando el contenedor corre dentro de la VM provisionada por Terraform. Una corrida vacía a producción real se siente igualito a una local — esa es la idea.

### Qué guarda el `.pkl`

El bundle serializado NO es solo el modelo: incluye también métricas y metadatos para que cualquiera que lo cargue después pueda saber con qué se entrenó sin tener que volver a correr nada.

```python
import joblib
bundle = joblib.load("telco_churn_logreg.pkl")
bundle.keys()
# dict_keys(['model', 'metrics', 'pipeline_metadata', 'training_run'])

bundle["model"].predict(X_nuevo)         # sklearn Pipeline listo para predict
bundle["metrics"]["test_roc_auc"]        # 0.8467
bundle["training_run"]["sklearn_version"]  # "1.5.2"  ← útil para reproducibilidad
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
