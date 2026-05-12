# DSRP — Machine Learning Engineering

![Aprendizaje Supervisado](modulo-1-aprendizaje-supervisado/assets/header.png)

**Profesor:** Miguel Arquez

Curso de Machine Learning y AI Engineering. Cada módulo es un conjunto de notebooks de Jupyter con teoría, fórmulas, visualizaciones y ejemplos prácticos sobre datasets reales de Kaggle.

## Módulos

- `modulo-1-aprendizaje-supervisado/` — Fundamentos de aprendizaje supervisado: regresión lineal, árboles de regresión, regresión logística y árboles de clasificación.
- `modulo-2-aprendizaje-no-supervisado/` — Aprendizaje no supervisado: introducción, clustering (K-Means y jerárquico), reducción de dimensionalidad (PCA + visualización de clusters) y reglas de asociación (Apriori).
- `modulo-3-introduccion-ai-engineering/` — Introducción a AI Engineering: LLMs y Transformers, APIs (OpenAI / Hugging Face) con chat completions / embeddings / multimodal, prompt engineering + parámetros + tokenización, alternativas (Ollama y Gemini), aplicación con LangChain (RAG mini), y comparación LLM vs modelos clásicos en problemas supervisados y no supervisados.

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

Esto instala numpy, pandas, scikit-learn, scipy, matplotlib, seaborn, statsmodels, mlxtend, jupyter, los SDK de AI engineering (openai, google-generativeai, ollama, huggingface-hub, tiktoken, python-dotenv) y LangChain (langchain, langchain-openai, langchain-community, langchain-chroma, langchain-text-splitters).

### 4. Descargar los datasets de Kaggle

Los notebooks usan tres datasets reales. **Descárgalos manualmente** desde Kaggle (tienes que aceptar las reglas de cada competencia/dataset una sola vez) y déjalos en la carpeta `data/` con los nombres indicados:

| Notebooks | Dataset | URL | Archivo en `data/` |
|---|---|---|---|
| Mód. 1 — 02, 03 | House Prices — Advanced Regression Techniques | https://www.kaggle.com/c/house-prices-advanced-regression-techniques | `housing_train.csv` (y opcionalmente `housing_test.csv`) |
| Mód. 1 — 04 / Mód. 2 — 02, 03 | Telco Customer Churn | https://www.kaggle.com/datasets/blastchar/telco-customer-churn | `WA_Fn-UseC_-Telco-Customer-Churn.csv` |
| Mód. 1 — 05 | Loan Default Dataset (Yasser H) | https://www.kaggle.com/datasets/yasserh/loan-default-dataset | `Loan_Default.csv` |

> El notebook `04_reglas_asociacion.ipynb` del módulo 2 **no necesita descarga**: genera transacciones sintéticas de canasta de mercado en el propio notebook.

### 4.b API keys y servicios externos para el módulo 3

El módulo 3 hace llamadas a APIs de LLMs. **No son obligatorias para leer el contenido**, pero si quieres ejecutar las celdas de ejemplo necesitas configurar las keys correspondientes en variables de entorno (recomendado: archivo `.env` en la raíz del repo, ya está en `.gitignore`).

| Notebook | Servicio | Variable | Dónde se obtiene |
|---|---|---|---|
| 02, 03, 05, 06 | OpenAI | `OPENAI_API_KEY` | https://platform.openai.com/api-keys |
| 02 | Hugging Face (opcional) | `HF_TOKEN` | https://huggingface.co/settings/tokens |
| 04 | Ollama (local, sin key) | — | https://ollama.com/download |
| 04 | Gemini | `GOOGLE_API_KEY` | https://aistudio.google.com/app/apikey |
| 06 | Reusa el dataset Telco (`WA_Fn-UseC_-Telco-Customer-Churn.csv`) ya descargado para módulos 1 y 2 | — | — |

Ejemplo de `.env`:

```
OPENAI_API_KEY=sk-...
HF_TOKEN=hf_...
GOOGLE_API_KEY=...
```

Para Ollama, además de instalarlo, descarga al menos un modelo: `ollama pull llama3.2` y `ollama pull nomic-embed-text` (para embeddings).

> El dataset de House Prices es una competencia de Kaggle: viene partido en `train.csv` (con la columna `SalePrice`) y `test.csv` (sin etiqueta, para enviar al leaderboard). En estos notebooks **solo usamos `housing_train.csv`** y lo partimos internamente con `train_test_split`. Renómbralo a `housing_train.csv` (y `housing_test.csv` si te lo quieres guardar) al moverlo a `data/`.

Estructura final de `data/` esperada:

```
data/
├── .gitkeep
├── housing_train.csv                             # nb 02, 03
├── housing_test.csv                              # opcional (no se usa en el módulo)
├── WA_Fn-UseC_-Telco-Customer-Churn.csv          # nb 04
└── Loan_Default.csv                              # nb 05
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
├── modulo-1-aprendizaje-supervisado/
│   ├── 01_introduccion_aprendizaje_supervisado.ipynb
│   ├── 02_regresion_lineal.ipynb
│   ├── 03_arboles_decision_regresion.ipynb
│   ├── 04_clasificacion_regresion_logistica.ipynb
│   └── 05_arboles_decision_clasificacion.ipynb
├── modulo-2-aprendizaje-no-supervisado/
│   ├── 01_introduccion_aprendizaje_no_supervisado.ipynb
│   ├── 02_clustering_kmeans_jerarquico.ipynb
│   ├── 03_reduccion_dimensionalidad_pca.ipynb
│   └── 04_reglas_asociacion.ipynb
└── modulo-3-introduccion-ai-engineering/
    ├── 01_introduccion_llms_y_genai.ipynb
    ├── 02_apis_openai_huggingface.ipynb
    ├── 03_prompt_engineering_y_tokenizacion.ipynb
    ├── 04_alternativas_ollama_y_gemini.ipynb
    ├── 05_aplicacion_langchain.ipynb
    └── 06_llm_vs_modelos_clasicos.ipynb
```
