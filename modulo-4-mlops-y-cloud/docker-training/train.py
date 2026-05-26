"""Entrena un modelo de churn sobre Telco descargando el CSV desde Azure Blob
Storage y empuja el .pkl resultante al mismo contenedor.

Pensado para correr dentro del contenedor Docker definido en `Dockerfile`.
Configuración por variables de entorno:

  AZURE_STORAGE_CONNECTION_STRING   (obligatoria)
  AZURE_STORAGE_CONTAINER           default: dsrp-modulo4
  INPUT_BLOB                        default: raw/telco_churn.csv
  OUTPUT_BLOB                       default: models/telco_churn_logreg.pkl
"""

from __future__ import annotations

import io
import os
import sys
import time
from pathlib import Path

import joblib
import pandas as pd
from azure.storage.blob import BlobServiceClient, ContentSettings
from sklearn.compose import ColumnTransformer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, roc_auc_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

CONN_STR = os.environ.get("AZURE_STORAGE_CONNECTION_STRING")
CONTAINER = os.environ.get("AZURE_STORAGE_CONTAINER", "dsrp-modulo4")
INPUT_BLOB = os.environ.get("INPUT_BLOB", "raw/telco_churn.csv")
OUTPUT_BLOB = os.environ.get("OUTPUT_BLOB", "models/telco_churn_logreg.pkl")
TARGET = "Churn"


def _log(msg: str) -> None:
    print(f"[train] {msg}", flush=True)


def load_dataframe(service: BlobServiceClient) -> pd.DataFrame:
    _log(f"descargando blob azure://{CONTAINER}/{INPUT_BLOB}")
    blob = service.get_blob_client(container=CONTAINER, blob=INPUT_BLOB)
    data = blob.download_blob().readall()
    df = pd.read_csv(io.BytesIO(data))
    _log(f"shape descargado: {df.shape}")
    return df


def preprocess(df: pd.DataFrame) -> tuple[pd.DataFrame, pd.Series]:
    df = df.copy()
    df["TotalCharges"] = pd.to_numeric(df["TotalCharges"], errors="coerce")
    df = df.dropna(subset=["TotalCharges"])
    df = df.drop(columns=["customerID"])
    y = (df[TARGET] == "Yes").astype(int)
    X = df.drop(columns=[TARGET])
    return X, y


def build_pipeline(X: pd.DataFrame) -> Pipeline:
    numeric = X.select_dtypes(include=["number"]).columns.tolist()
    categorical = X.select_dtypes(include=["object"]).columns.tolist()
    pre = ColumnTransformer(
        [
            ("num", StandardScaler(), numeric),
            ("cat", OneHotEncoder(handle_unknown="ignore"), categorical),
        ]
    )
    return Pipeline([("pre", pre), ("clf", LogisticRegression(max_iter=1000, n_jobs=-1))])


def upload_model(service: BlobServiceClient, local: Path) -> str:
    _log(f"subiendo modelo a azure://{CONTAINER}/{OUTPUT_BLOB}")
    blob = service.get_blob_client(container=CONTAINER, blob=OUTPUT_BLOB)
    with local.open("rb") as f:
        blob.upload_blob(
            f,
            overwrite=True,
            content_settings=ContentSettings(content_type="application/octet-stream"),
        )
    return blob.url


def main() -> int:
    if not CONN_STR:
        _log("FATAL: AZURE_STORAGE_CONNECTION_STRING no está definida")
        return 2

    t0 = time.perf_counter()
    service = BlobServiceClient.from_connection_string(CONN_STR)

    df = load_dataframe(service)
    X, y = preprocess(df)
    X_tr, X_te, y_tr, y_te = train_test_split(X, y, test_size=0.2, random_state=42, stratify=y)

    pipe = build_pipeline(X_tr)
    _log("entrenando LogisticRegression con preprocesamiento...")
    pipe.fit(X_tr, y_tr)

    proba = pipe.predict_proba(X_te)[:, 1]
    preds = (proba >= 0.5).astype(int)
    acc = accuracy_score(y_te, preds)
    auc = roc_auc_score(y_te, proba)
    _log(f"métricas: accuracy={acc:.4f}  roc_auc={auc:.4f}")

    out = Path("/tmp/telco_churn_logreg.pkl")
    joblib.dump({"model": pipe, "metrics": {"accuracy": acc, "roc_auc": auc}}, out)
    _log(f"modelo serializado en {out} ({out.stat().st_size:,} bytes)")

    url = upload_model(service, out)
    _log(f"OK — modelo disponible en {url}")
    _log(f"tiempo total: {time.perf_counter() - t0:.1f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
