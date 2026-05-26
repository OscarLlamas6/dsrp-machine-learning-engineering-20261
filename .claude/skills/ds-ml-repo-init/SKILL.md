---
name: ds-ml-repo-init
description: Bootstrap a brand-new Data Science / Machine Learning project repository with a sensible layout, pyproject.toml using uv, .gitignore, ruff/black config, a starter notebook, Dockerfile, Makefile and a GitHub Actions CI workflow. Use this skill whenever the user says they want to "start a new ML project", "create a new data science repo", "scaffold an ML repository", "initialize an ML project", or mentions setting up a fresh ML / DS / AI codebase — even if they don't say the word "skill". The user typically wants a working layout in seconds, not a long discussion about it.
---

# DS / ML Repository Bootstrapper

This skill scaffolds an opinionated layout for a Data Science / Machine Learning project. It is intentionally minimal — every file has a clear reason to exist. Adapt names and dependencies to the user's stack; do not blindly paste.

## When to use it

Trigger when the user says any of:
- "let's start a new ML project"
- "create a data science repo"
- "scaffold / bootstrap an ML repository"
- "init a new ds project named X"
- "I want a fresh project for training X"

If they're already deep inside an existing repo and just adding a feature, **do not** use this skill — it would clobber things.

## Capture intent (one short exchange, then go)

Before generating files, confirm the following in a single message:

1. **Project name** (kebab-case, becomes the directory and package slug).
2. **Primary task type**: tabular / NLP / vision / time-series / LLM-app. Drives the default deps.
3. **Cloud target**: none / AWS / Azure / GCP. Drives example storage code.
4. **Containerized?** y/n. If yes, include the Dockerfile; if no, skip.
5. **CI?** y/n. If yes, include `.github/workflows/ci.yml`.

If the user already gave answers in their prompt, skip the question and reflect them back in one sentence.

## Target layout

```
<project-name>/
├── README.md
├── pyproject.toml                # uv-managed, Python ≥3.11
├── .python-version
├── .gitignore
├── .env.example
├── Makefile                      # train / test / lint / docker
├── Dockerfile                    # optional
├── .dockerignore                 # only if Dockerfile present
├── .github/
│   └── workflows/
│       └── ci.yml                # ruff + pytest, optional
├── data/
│   ├── .gitkeep
│   ├── raw/                      # never edited by hand
│   ├── interim/                  # intermediate transforms
│   └── processed/                # ready-for-model
├── notebooks/
│   └── 01_eda.ipynb              # empty starter
├── src/
│   └── <project_snake>/
│       ├── __init__.py
│       ├── config.py             # env vars, paths
│       ├── data.py               # load / split
│       ├── features.py           # transforms, preprocessors
│       ├── train.py              # entry point: `python -m <pkg>.train`
│       ├── evaluate.py
│       └── inference.py          # load .pkl, predict()
├── tests/
│   ├── __init__.py
│   └── test_smoke.py
└── models/
    └── .gitkeep                  # trained .pkl artifacts (gitignored)
```

Rules:
- **`src/<pkg>/` not flat scripts.** Imports survive refactors; flat scripts do not.
- **Notebooks are exploratory, not production.** Anything reusable migrates to `src/`.
- **`data/` is gitignored except `.gitkeep`.** Real data goes in object storage, see `references/cloud_snippets.md`.
- **`models/` is gitignored.** Artifacts go in Blob Storage / S3 / GCS.

## How to generate

Generate every file with `Write`. Do not run `mkdir` — `Write` creates parents.

After generating, run:
```bash
cd <project-name>
git init -q && git add -A && git commit -q -m "chore: initial scaffold"
uv sync
```

Then tell the user three things:
1. Where to put the dataset (`data/raw/`).
2. The first command to run (`uv run python -m <pkg>.train`).
3. The next file they should fill in (`src/<pkg>/data.py`).

## File templates

The actual file contents live in `references/templates.md` (long, kept out of context until needed). Read it only when you're ready to write files — do not preload.

For cloud-specific snippets (Blob / S3 / GCS upload, environment-variable patterns, secret handling), see `references/cloud_snippets.md`.

## Anti-patterns to avoid

- **Do not** generate a `setup.py`. Use `pyproject.toml` only.
- **Do not** create a top-level `utils.py` — put helpers inside the package.
- **Do not** invent dependencies that the user didn't ask for (no `lightgbm` unless they said tabular boosting, no `torch` unless they said deep learning).
- **Do not** commit a `.env` file. Always `.env.example` only.
- **Do not** name notebooks generically (`notebook1.ipynb`). Use `NN_topic.ipynb`.
- **Do not** dump every README section. Keep the generated README short — the user will expand it.

## Confirmation

End by asking: "Do you want me to also create an initial commit and push to a new GitHub repo (`gh repo create`)?" — only if `gh` is installed.
