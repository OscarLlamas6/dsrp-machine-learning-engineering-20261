"""Entrena un modelo de churn sobre Telco descargando el CSV desde Azure Blob
Storage y empuja el .pkl resultante al mismo contenedor.

Diseñado para correr DENTRO del contenedor Docker definido en `Dockerfile`,
pero también funciona local si tienes las env vars puestas. Cuando corre en
la VM provisionada por Terraform, los logs aparecen en
`sudo journalctl -u dsrp-trainer.service`.

Configuración por variables de entorno:

  AZURE_STORAGE_CONNECTION_STRING   (obligatoria)
  AZURE_STORAGE_CONTAINER           default: dsrp-modulo4
  INPUT_BLOB                        default: raw/telco_churn.csv
  OUTPUT_BLOB                       default: models/telco_churn_logreg.pkl
  RUN_ID                            default: timestamp UTC
"""

from __future__ import annotations

import io
import os
import platform
import resource
import socket
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import sklearn
from azure.storage.blob import BlobServiceClient, ContentSettings
from sklearn.compose import ColumnTransformer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

CONN_STR = os.environ.get("AZURE_STORAGE_CONNECTION_STRING")
CONTAINER = os.environ.get("AZURE_STORAGE_CONTAINER", "dsrp-modulo4")
INPUT_BLOB = os.environ.get("INPUT_BLOB", "raw/telco_churn.csv")
OUTPUT_BLOB = os.environ.get("OUTPUT_BLOB", "models/telco_churn_logreg.pkl")
RUN_ID = os.environ.get("RUN_ID", datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
TARGET = "Churn"

# ─── helpers de logging ──────────────────────────────────────────────────────


def _log(msg: str = "") -> None:
    """Línea de log normal. Prefijo `[train]` para grepearlo en journalctl."""
    print(f"[train] {msg}", flush=True)


def _section(title: str) -> None:
    """Encabezado de sección — facilita escanear logs largos."""
    bar = "─" * (len(title) + 4)
    print(f"\n[train] {bar}", flush=True)
    print(f"[train]  {title}", flush=True)
    print(f"[train] {bar}", flush=True)


def _rss_mb() -> float:
    """Memoria residente del proceso en MB. Linux/macOS only (stdlib)."""
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    # Linux reporta en KB; macOS en bytes.
    return rss / 1024 if sys.platform.startswith("linux") else rss / (1024 * 1024)


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ─── pasos del pipeline ──────────────────────────────────────────────────────


def log_runtime_metadata() -> None:
    """Imprime metadatos del runtime — útil para auditoría de qué corrió donde."""
    _section("RUNTIME")
    _log(f"run_id          = {RUN_ID}")
    _log(f"started_at      = {_now_iso()}")
    _log(f"host            = {socket.gethostname()}")
    _log(f"python          = {platform.python_version()} ({platform.python_implementation()})")
    _log(f"sklearn         = {sklearn.__version__}")
    _log(f"numpy           = {np.__version__}")
    _log(f"pandas          = {pd.__version__}")
    _log(f"platform        = {platform.platform()}")
    _log(f"container       = azure://{CONTAINER}")
    _log(f"input_blob      = {INPUT_BLOB}")
    _log(f"output_blob     = {OUTPUT_BLOB}")
    _log(f"rss_inicial_mb  = {_rss_mb():.1f}")


def load_dataframe(service: BlobServiceClient) -> pd.DataFrame:
    _section("DESCARGA DATOS")
    _log(f"GET azure://{CONTAINER}/{INPUT_BLOB}")
    t0 = time.perf_counter()
    blob = service.get_blob_client(container=CONTAINER, blob=INPUT_BLOB)
    data = blob.download_blob().readall()
    dl_seconds = time.perf_counter() - t0
    _log(f"descargado      : {len(data):,} bytes en {dl_seconds:.2f}s ({len(data) / dl_seconds / 1024 / 1024:.1f} MiB/s)")

    df = pd.read_csv(io.BytesIO(data))
    _log(f"parseado        : {df.shape[0]:,} filas × {df.shape[1]} columnas")
    return df


def describe_dataset(df: pd.DataFrame) -> None:
    _section("DATASET")
    _log(f"shape           : {df.shape}")
    _log(f"memoria df_mb   : {df.memory_usage(deep=True).sum() / 1024 / 1024:.2f}")
    _log(f"nulos totales   : {df.isna().sum().sum():,}")

    dtypes = df.dtypes.value_counts()
    _log(f"dtypes          : {dict(dtypes)}")

    # Balance de clases del target
    target_counts = df[TARGET].value_counts()
    total = target_counts.sum()
    _log(f"target ({TARGET}):")
    for cls, count in target_counts.items():
        _log(f"  - {cls:<5} {count:>5,}  ({count / total:.1%})")


def preprocess(df: pd.DataFrame) -> tuple[pd.DataFrame, pd.Series]:
    _section("PREPROCESAMIENTO")
    df = df.copy()

    n_before = len(df)
    df["TotalCharges"] = pd.to_numeric(df["TotalCharges"], errors="coerce")
    n_invalid = df["TotalCharges"].isna().sum()
    df = df.dropna(subset=["TotalCharges"])
    _log(f"TotalCharges    : {n_invalid} filas con valores no-numéricos descartadas ({n_invalid / n_before:.2%})")

    df = df.drop(columns=["customerID"])
    _log(f"dropped         : customerID (id único, no informativo)")

    y = (df[TARGET] == "Yes").astype(int)
    X = df.drop(columns=[TARGET])
    _log(f"X shape         : {X.shape}")
    _log(f"y churn rate    : {y.mean():.3%}")
    return X, y


def build_pipeline(X: pd.DataFrame) -> tuple[Pipeline, dict]:
    _section("PIPELINE")
    numeric = X.select_dtypes(include=["number"]).columns.tolist()
    categorical = X.select_dtypes(include=["object"]).columns.tolist()

    _log(f"numéricas ({len(numeric)})     : {numeric}")
    _log(f"categóricas ({len(categorical)}) : {categorical}")

    pre = ColumnTransformer(
        [
            ("num", StandardScaler(), numeric),
            ("cat", OneHotEncoder(handle_unknown="ignore"), categorical),
        ]
    )
    pipe = Pipeline([("pre", pre), ("clf", LogisticRegression(max_iter=1000, n_jobs=-1))])

    metadata = {
        "n_numeric_cols": len(numeric),
        "n_categorical_cols": len(categorical),
        "numeric_cols": numeric,
        "categorical_cols": categorical,
        "estimator": "LogisticRegression(max_iter=1000)",
    }
    return pipe, metadata


def train_and_eval(pipe: Pipeline, X_tr, X_te, y_tr, y_te) -> dict:
    _section("ENTRENAMIENTO")
    _log(f"X_train         : {X_tr.shape}")
    _log(f"X_test          : {X_te.shape}")
    _log(f"y_train churn   : {y_tr.mean():.3%}")
    _log(f"y_test  churn   : {y_te.mean():.3%}")

    t0 = time.perf_counter()
    pipe.fit(X_tr, y_tr)
    train_seconds = time.perf_counter() - t0

    # Cuántas features quedaron después del ColumnTransformer (OneHot expande las categóricas).
    n_features_out = pipe.named_steps["pre"].transform(X_tr.head(1)).shape[1]
    _log(f"features OHE    : {n_features_out}  (post one-hot encoding)")
    _log(f"fit duration_s  : {train_seconds:.2f}")
    _log(f"rss_post_fit_mb : {_rss_mb():.1f}")

    _section("MÉTRICAS")
    # Train
    proba_tr = pipe.predict_proba(X_tr)[:, 1]
    preds_tr = (proba_tr >= 0.5).astype(int)
    train_acc = accuracy_score(y_tr, preds_tr)
    train_auc = roc_auc_score(y_tr, proba_tr)

    # Test
    proba_te = pipe.predict_proba(X_te)[:, 1]
    preds_te = (proba_te >= 0.5).astype(int)
    test_acc = accuracy_score(y_te, preds_te)
    test_auc = roc_auc_score(y_te, proba_te)
    test_prec = precision_score(y_te, preds_te)
    test_rec = recall_score(y_te, preds_te)
    test_f1 = f1_score(y_te, preds_te)
    cm = confusion_matrix(y_te, preds_te)

    _log(f"train accuracy  : {train_acc:.4f}")
    _log(f"train roc_auc   : {train_auc:.4f}")
    _log(f"test  accuracy  : {test_acc:.4f}")
    _log(f"test  roc_auc   : {test_auc:.4f}")
    _log(f"test  precision : {test_prec:.4f}")
    _log(f"test  recall    : {test_rec:.4f}")
    _log(f"test  f1        : {test_f1:.4f}")
    _log(f"overfit gap     : {train_acc - test_acc:+.4f}  (train_acc - test_acc)")
    _log("confusion matrix (rows=actual, cols=pred):")
    _log(f"              pred_no_churn  pred_churn")
    _log(f"  no_churn   {cm[0, 0]:>13,d}  {cm[0, 1]:>10,d}")
    _log(f"  churn      {cm[1, 0]:>13,d}  {cm[1, 1]:>10,d}")

    return {
        "n_features_out": int(n_features_out),
        "train_seconds": train_seconds,
        "train_accuracy": float(train_acc),
        "train_roc_auc": float(train_auc),
        "test_accuracy": float(test_acc),
        "test_roc_auc": float(test_auc),
        "test_precision": float(test_prec),
        "test_recall": float(test_rec),
        "test_f1": float(test_f1),
        "confusion_matrix": cm.tolist(),
    }


def upload_model(service: BlobServiceClient, local: Path) -> str:
    _section("UPLOAD MODELO")
    _log(f"PUT azure://{CONTAINER}/{OUTPUT_BLOB}")
    t0 = time.perf_counter()
    blob = service.get_blob_client(container=CONTAINER, blob=OUTPUT_BLOB)
    with local.open("rb") as f:
        blob.upload_blob(
            f,
            overwrite=True,
            content_settings=ContentSettings(content_type="application/octet-stream"),
        )
    up_seconds = time.perf_counter() - t0
    size = local.stat().st_size
    _log(f"subido          : {size:,} bytes en {up_seconds:.2f}s ({size / up_seconds / 1024 / 1024:.1f} MiB/s)")
    return blob.url


def main() -> int:
    if not CONN_STR:
        _log("FATAL: AZURE_STORAGE_CONNECTION_STRING no está definida")
        return 2

    t0 = time.perf_counter()
    log_runtime_metadata()

    service = BlobServiceClient.from_connection_string(CONN_STR)

    df = load_dataframe(service)
    describe_dataset(df)

    X, y = preprocess(df)
    X_tr, X_te, y_tr, y_te = train_test_split(X, y, test_size=0.2, random_state=42, stratify=y)

    pipe, pipe_metadata = build_pipeline(X_tr)
    metrics = train_and_eval(pipe, X_tr, X_te, y_tr, y_te)

    # Bundle: modelo + métricas + metadata. Cualquiera que cargue el .pkl
    # puede saber con qué se entrenó sin tener que volver a correr nada.
    bundle = {
        "model": pipe,
        "metrics": metrics,
        "pipeline_metadata": pipe_metadata,
        "training_run": {
            "run_id": RUN_ID,
            "started_at": _now_iso(),
            "input_blob": INPUT_BLOB,
            "output_blob": OUTPUT_BLOB,
            "dataset_rows": int(len(df)),
            "train_rows": int(len(X_tr)),
            "test_rows": int(len(X_te)),
            "sklearn_version": sklearn.__version__,
            "python_version": platform.python_version(),
        },
    }

    out = Path("/tmp/telco_churn_logreg.pkl")
    joblib.dump(bundle, out)
    _section("SERIALIZACIÓN")
    _log(f"pickle path     : {out}")
    _log(f"pickle bytes    : {out.stat().st_size:,}")

    url = upload_model(service, out)

    _section("RESUMEN")
    total = time.perf_counter() - t0
    _log(f"OK              : modelo disponible en {url}")
    _log(f"duración_total_s: {total:.2f}")
    _log(f"rss_final_mb    : {_rss_mb():.1f}")
    _log(f"finished_at     : {_now_iso()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
