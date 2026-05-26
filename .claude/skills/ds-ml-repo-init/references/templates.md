# File templates for `ds-ml-repo-init`

Substitute these placeholders before writing:

- `{{PROJECT}}` → kebab-case name (`telco-churn`)
- `{{PKG}}` → snake_case package (`telco_churn`)
- `{{PYTHON_VERSION}}` → e.g. `3.12`
- `{{TASK_DEPS}}` → resolved from task type (see bottom)

---

## `README.md`

```markdown
# {{PROJECT}}

Short description of what this project does, written in one sentence.

## Setup

```bash
uv sync
cp .env.example .env  # then fill in secrets
```

## Train

```bash
uv run python -m {{PKG}}.train
```

## Layout

- `src/{{PKG}}/` — production code
- `notebooks/` — exploration only
- `data/raw/` — drop your input files here (gitignored)
- `models/` — trained artifacts (gitignored)
```

---

## `pyproject.toml`

```toml
[project]
name = "{{PROJECT}}"
version = "0.1.0"
description = ""
requires-python = ">={{PYTHON_VERSION}}"
dependencies = [
    "pandas>=2.2",
    "numpy>=1.26",
    "scikit-learn>=1.5",
    "python-dotenv>=1.0",
    {{TASK_DEPS}}
]

[dependency-groups]
dev = [
    "pytest>=8",
    "ruff>=0.6",
    "ipykernel>=6.29",
    "jupyter>=1.1",
]

[tool.ruff]
line-length = 100
target-version = "py{{PYTHON_VERSION_NODOT}}"

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B", "SIM"]
```

---

## `.python-version`

```
{{PYTHON_VERSION}}
```

---

## `.gitignore`

```gitignore
# Python
__pycache__/
*.py[cod]
.venv/
.python-version

# Notebooks
.ipynb_checkpoints/

# Data + models — never commit
data/*
!data/.gitkeep
!data/raw/.gitkeep
!data/interim/.gitkeep
!data/processed/.gitkeep
models/*
!models/.gitkeep

# Secrets
.env
*.key
*.pem

# OS
.DS_Store

# Build
dist/
build/
*.egg-info/
```

---

## `.env.example`

```bash
# Object storage (pick the one for your cloud)
AZURE_STORAGE_CONNECTION_STRING=
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
GOOGLE_APPLICATION_CREDENTIALS=

# Experiment tracking (optional)
MLFLOW_TRACKING_URI=
WANDB_API_KEY=
```

---

## `Makefile`

```makefile
.PHONY: install train test lint docker

install:
	uv sync

train:
	uv run python -m {{PKG}}.train

test:
	uv run pytest -q

lint:
	uv run ruff check src tests
	uv run ruff format --check src tests

docker:
	docker build -t {{PROJECT}}:latest .
```

---

## `Dockerfile` (only if user wants containerized)

```dockerfile
FROM python:{{PYTHON_VERSION}}-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app

RUN pip install --no-cache-dir uv

COPY pyproject.toml ./
RUN uv pip install --system --no-cache .

COPY src ./src
ENTRYPOINT ["python", "-m", "{{PKG}}.train"]
```

---

## `.dockerignore`

```
.venv/
.git/
.github/
data/
models/
notebooks/
tests/
*.ipynb
.env
__pycache__/
```

---

## `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v3
      - run: uv sync
      - run: uv run ruff check src tests
      - run: uv run pytest -q
```

---

## `src/{{PKG}}/__init__.py`

```python
__version__ = "0.1.0"
```

---

## `src/{{PKG}}/config.py`

```python
import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

ROOT = Path(__file__).resolve().parents[2]
DATA_RAW = ROOT / "data" / "raw"
DATA_PROCESSED = ROOT / "data" / "processed"
MODELS_DIR = ROOT / "models"

AZURE_CONN = os.getenv("AZURE_STORAGE_CONNECTION_STRING", "")
```

---

## `src/{{PKG}}/data.py`

```python
import pandas as pd
from sklearn.model_selection import train_test_split

from .config import DATA_RAW


def load_raw(filename: str) -> pd.DataFrame:
    return pd.read_csv(DATA_RAW / filename)


def split(df: pd.DataFrame, target: str, test_size: float = 0.2, seed: int = 42):
    X = df.drop(columns=[target])
    y = df[target]
    return train_test_split(X, y, test_size=test_size, random_state=seed, stratify=y if y.nunique() < 20 else None)
```

---

## `src/{{PKG}}/train.py`

```python
import joblib
from sklearn.dummy import DummyClassifier

from .config import MODELS_DIR
from .data import load_raw, split


def main() -> None:
    # TODO: replace with real dataset + target column
    df = load_raw("YOUR_FILE.csv")
    X_train, X_test, y_train, y_test = split(df, target="TARGET_COLUMN")

    model = DummyClassifier(strategy="most_frequent")
    model.fit(X_train, y_train)
    print(f"score = {model.score(X_test, y_test):.4f}")

    MODELS_DIR.mkdir(exist_ok=True)
    out = MODELS_DIR / "model.pkl"
    joblib.dump(model, out)
    print(f"saved → {out}")


if __name__ == "__main__":
    main()
```

---

## `src/{{PKG}}/evaluate.py`

```python
from sklearn.metrics import classification_report


def evaluate(model, X, y) -> str:
    return classification_report(y, model.predict(X))
```

---

## `src/{{PKG}}/inference.py`

```python
import joblib
import pandas as pd

from .config import MODELS_DIR


def load_model(path: str = "model.pkl"):
    return joblib.load(MODELS_DIR / path)


def predict(model, X: pd.DataFrame):
    return model.predict(X)
```

---

## `tests/__init__.py`

(empty file)

---

## `tests/test_smoke.py`

```python
def test_package_imports():
    import {{PKG}}  # noqa: F401
```

---

## `notebooks/01_eda.ipynb`

Minimal empty notebook:

```json
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": ["# 01 — Exploratory Data Analysis\n", "\n", "First look at the dataset."]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": ["import pandas as pd\n", "from {{PKG}}.config import DATA_RAW\n", "\n", "# df = pd.read_csv(DATA_RAW / 'YOUR_FILE.csv')\n", "# df.head()"]
  }
 ],
 "metadata": {
  "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"}
 },
 "nbformat": 4,
 "nbformat_minor": 5
}
```

---

## Task-type → dependencies

Substitute `{{TASK_DEPS}}` with one of:

| Task | Deps |
|---|---|
| tabular | `"lightgbm>=4.5", "xgboost>=2.1"` |
| NLP | `"transformers>=4.45", "datasets>=3.0", "torch>=2.4"` |
| vision | `"torch>=2.4", "torchvision>=0.19", "pillow>=10"` |
| time-series | `"statsmodels>=0.14", "prophet>=1.1"` |
| LLM-app | `"openai>=1.55", "langchain>=0.3", "tiktoken>=0.8"` |
