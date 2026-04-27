# DSRP — Machine Learning Engineering

![Aprendizaje Supervisado](modulo-1-aprendizaje-supervisado/assets/header.png)

Curso de Machine Learning y AI Engineering. Cada módulo es un conjunto de notebooks de Jupyter con teoría, fórmulas, visualizaciones y ejemplos prácticos sobre datasets reales de Kaggle.

## Módulos

- `modulo-1-aprendizaje-supervisado/` — Fundamentos de aprendizaje supervisado: regresión lineal, árboles de regresión, regresión logística y árboles de clasificación.

## Requisitos

- **Python 3.14+** (la versión está fijada en `.python-version`; `uv` la instala automáticamente si no la tienes)
- **uv** como gestor de entorno y paquetes (https://docs.astral.sh/uv/)
- **git**
- Una cuenta de **Kaggle** para descargar los datasets (gratis)

## Configuración inicial — paso a paso

### 1. Clonar el repositorio

```bash
git clone <url-del-repo> dsrp-machine-learning-engineering
cd dsrp-machine-learning-engineering
```

### 2. Instalar `uv` (si no lo tienes)

macOS / Linux:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Windows (PowerShell):

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

Verifica:

```bash
uv --version
```

### 3. Crear el entorno e instalar las dependencias

`uv` lee `pyproject.toml` y `uv.lock` y crea el entorno virtual `.venv/` automáticamente:

```bash
uv sync
```

Esto instala numpy, pandas, scikit-learn, matplotlib, seaborn, statsmodels y jupyter.

### 4. Descargar los datasets de Kaggle

Los notebooks usan tres datasets reales. **Descárgalos manualmente** desde Kaggle (tienes que aceptar las reglas de cada competencia/dataset una sola vez) y déjalos en la carpeta `data/` con los nombres indicados:

| Notebooks | Dataset | URL | Archivo en `data/` |
|---|---|---|---|
| 02, 03 | House Prices — Advanced Regression Techniques | https://www.kaggle.com/c/house-prices-advanced-regression-techniques | `housing_train.csv` (y opcionalmente `housing_test.csv`) |
| 04, 05 | Telco Customer Churn | https://www.kaggle.com/datasets/blastchar/telco-customer-churn | `WA_Fn-UseC_-Telco-Customer-Churn.csv` |
| (referencia) | Loan Default Dataset (Yasser H) | https://www.kaggle.com/datasets/yasserh/loan-default-dataset | `Loan_Default.csv` |

> El dataset de House Prices es una competencia de Kaggle: viene partido en `train.csv` (con la columna `SalePrice`) y `test.csv` (sin etiqueta, para enviar al leaderboard). En estos notebooks **solo usamos `housing_train.csv`** y lo partimos internamente con `train_test_split`. Renómbralo a `housing_train.csv` (y `housing_test.csv` si te lo quieres guardar) al moverlo a `data/`.

Estructura final de `data/` esperada:

```
data/
├── .gitkeep
├── housing_train.csv
├── housing_test.csv                              # opcional (no se usa en el módulo)
├── WA_Fn-UseC_-Telco-Customer-Churn.csv
└── Loan_Default.csv                              # opcional (referencia)
```

> Los CSV están en `.gitignore` (carpeta `data/` ignorada salvo `.gitkeep`), así que no se suben al repositorio.

#### Alternativa con la CLI de Kaggle

Si prefieres usar la CLI oficial:

```bash
uv pip install kaggle
# coloca tu token en ~/.kaggle/kaggle.json (ver https://www.kaggle.com/docs/api)

kaggle competitions download -c house-prices-advanced-regression-techniques -p data
unzip -o data/house-prices-advanced-regression-techniques.zip -d data
mv data/train.csv data/housing_train.csv
mv data/test.csv  data/housing_test.csv

kaggle datasets download -d blastchar/telco-customer-churn -p data
unzip -o data/telco-customer-churn.zip -d data

kaggle datasets download -d yasserh/loan-default-dataset -p data
unzip -o data/loan-default-dataset.zip -d data
```

### 5. Abrir Jupyter

Desde la **raíz del repositorio**:

```bash
uv run jupyter lab
```

Esto levanta JupyterLab usando el entorno `.venv/` creado por `uv`. Navega a `modulo-1-aprendizaje-supervisado/` y abre los notebooks en orden (01 → 05).

> Si prefieres notebook clásico: `uv run jupyter notebook`.

## Ejecutar un script suelto

```bash
uv run python ruta/al/script.py
```

## Agregar dependencias nuevas

```bash
uv add <paquete>
```

## Estructura del repositorio

```
.
├── README.md
├── pyproject.toml
├── uv.lock
├── .python-version
├── data/                              # datasets locales (no versionados)
└── modulo-1-aprendizaje-supervisado/
    ├── 01_introduccion_aprendizaje_supervisado.ipynb
    ├── 02_regresion_lineal.ipynb
    ├── 03_arboles_decision_regresion.ipynb
    ├── 04_clasificacion_regresion_logistica.ipynb
    └── 05_arboles_decision_clasificacion.ipynb
```
