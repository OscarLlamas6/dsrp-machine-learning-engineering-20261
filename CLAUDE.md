# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

DSRP "Machine Learning Engineering" course material (instructor: Miguel Arquez). Content is **Jupyter notebooks in Spanish** organized into four modules — not an application. The only non-notebook code lives in `modulo-4-mlops-y-cloud/` (Docker trainer, Terraform, GitHub Action, a Claude Code skill).

Modules:
- `modulo-1-aprendizaje-supervisado/` — supervised learning (linear/logistic regression, decision trees)
- `modulo-2-aprendizaje-no-supervisado/` — clustering, PCA, association rules
- `modulo-3-introduccion-ai-engineering/` — LLM APIs (OpenAI / HF / Ollama / Gemini), prompt engineering, LangChain RAG
- `modulo-4-mlops-y-cloud/` — Docker, Azure Blob, GitHub Actions, Terraform

## Environment & common commands

Python is pinned to **3.14+** (`.python-version`) and managed with **uv**. Dependencies in `pyproject.toml` / `uv.lock`. Do **not** use pip directly — always go through uv.

```bash
uv sync                            # install / refresh the .venv
uv run jupyter lab                 # launch notebooks (run from repo root)
uv run python <script.py>          # run a one-off script in the env
uv add <pkg>                       # add a dependency
```

There are **no tests, no linter, no build step** for the notebooks themselves. The only "build" is the module-4 Docker image (CI-driven, see below).

## Datasets

Notebooks read CSVs from `data/`, which is gitignored except `.gitkeep`. Required files (download manually from Kaggle, see `README.md` §4 for URLs):
- `data/housing_train.csv` — House Prices (módulo 1 nb 02, 03)
- `data/WA_Fn-UseC_-Telco-Customer-Churn.csv` — Telco Churn (módulos 1, 2, 3 nb 06, módulo 4)
- `data/Loan_Default.csv` — Loan Default (módulo 1 nb 05)

If a notebook errors on a missing CSV, point the user to the README table rather than inventing a path.

## Secrets (módulo 3 and 4)

`.env` at repo root is gitignored. Used by:
- Módulo 3: `OPENAI_API_KEY`, `HF_TOKEN` (optional), `GOOGLE_API_KEY`. Ollama is local (no key) but needs `ollama pull llama3.2` + `ollama pull nomic-embed-text`.
- Módulo 4: `AZURE_STORAGE_CONNECTION_STRING`, `AZURE_STORAGE_CONTAINER`, `AZURE_SUBSCRIPTION_ID`.

`*.pkl`, `.env`, `ai.env`, `terraform.tfvars`, and `modulo-3-introduccion-ai-engineering/*.mp3|*.png` (outputs from TTS/DALL·E demos) are all gitignored — don't try to commit them.

## Módulo 4 — the only "engineering" surface

This module is a small but real pipeline; it's where most non-notebook work happens.

**Data flow:** repo → GitHub Actions builds `modulo-4-mlops-y-cloud/docker-training/` → publishes to `ghcr.io/<owner>/dsrp-modulo4-trainer:latest` → Terraform-provisioned Azure VM pulls the image via cloud-init + a `dsrp-trainer.service` systemd unit → the container downloads `raw/telco_churn.csv` from Azure Blob, trains a sklearn `LogisticRegression` pipeline (`docker-training/train.py`), and pushes the `.pkl` back to the same container under `models/`.

Key files to read together for any change here:
- `.github/workflows/build-modulo4-image.yml` — triggers on `docker-training/**` paths only
- `modulo-4-mlops-y-cloud/docker-training/{Dockerfile,train.py,requirements.txt}` — the trainer; env-var driven
- `modulo-4-mlops-y-cloud/terraform/{main.tf,variables.tf,cloud-init.yaml,Taskfile.yml}` — VM + cloud-init that runs the trainer

**Terraform is driven by go-task, not raw `terraform` commands.** Run everything from `modulo-4-mlops-y-cloud/terraform/`:

```bash
task backend:setup          # one-time: creates remote state account in Azure
task init                   # terraform init with backend.hcl
task plan / task apply      # apply uses tfplan if present, else -auto-approve with tfvars
task ssh / task logs        # operate the VM
task trainer:rerun          # re-run systemd oneshot without redeploying
task destroy                # tear down the VM RG (state RG survives)
task backend:destroy        # also tear down the state RG
```

State lives in a remote Azure storage account with **versioning + 30-day soft-delete**. `backend.hcl` and `dsrp-values.tfvars` are gitignored — `dsrp-values.tfvars.example` is the template.

The CI workflow only fires on changes under `modulo-4-mlops-y-cloud/docker-training/**` or the workflow file itself — edits to notebooks or Terraform won't rebuild the image.

## Working in notebooks

- Notebook prose is Spanish; preserve language when editing markdown cells.
- `.ipynb_checkpoints/` is gitignored; ignore it when grepping/listing.
- `*.pkl` artifacts that appear next to notebooks (e.g. `modelo_house_lr.pkl`) are gitignored outputs — they regenerate when the notebook runs.

## The `ds-ml-repo-init` skill

`modulo-4-mlops-y-cloud/skills/ds-ml-repo-init/SKILL.md` is a Claude Code skill that scaffolds **new** DS/ML repos. It is course material to be shown to students, not something to invoke against this repo. Don't run it here.
