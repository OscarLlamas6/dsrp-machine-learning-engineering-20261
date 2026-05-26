# Cloud snippets

Drop the relevant snippet into `src/{{PKG}}/storage.py` based on the user's cloud choice.

## Azure Blob Storage

```python
import os
from azure.storage.blob import BlobServiceClient

def _client() -> BlobServiceClient:
    return BlobServiceClient.from_connection_string(os.environ["AZURE_STORAGE_CONNECTION_STRING"])

def upload(local_path: str, container: str, blob_name: str) -> None:
    blob = _client().get_blob_client(container=container, blob=blob_name)
    with open(local_path, "rb") as f:
        blob.upload_blob(f, overwrite=True)

def download(container: str, blob_name: str, local_path: str) -> None:
    blob = _client().get_blob_client(container=container, blob=blob_name)
    with open(local_path, "wb") as f:
        f.write(blob.download_blob().readall())
```

Dep: `"azure-storage-blob>=12.22"`
Env: `AZURE_STORAGE_CONNECTION_STRING`

## AWS S3

```python
import boto3

def upload(local_path: str, bucket: str, key: str) -> None:
    boto3.client("s3").upload_file(local_path, bucket, key)

def download(bucket: str, key: str, local_path: str) -> None:
    boto3.client("s3").download_file(bucket, key, local_path)
```

Dep: `"boto3>=1.35"`
Env: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION` (or use an IAM role).

## GCP GCS

```python
from google.cloud import storage

def upload(local_path: str, bucket: str, blob_name: str) -> None:
    storage.Client().bucket(bucket).blob(blob_name).upload_from_filename(local_path)

def download(bucket: str, blob_name: str, local_path: str) -> None:
    storage.Client().bucket(bucket).blob(blob_name).download_to_filename(local_path)
```

Dep: `"google-cloud-storage>=2.18"`
Env: `GOOGLE_APPLICATION_CREDENTIALS` pointing at a service-account JSON.

## Secret-handling rule

Never hardcode credentials. Always:
1. Read from env vars via `os.getenv(...)`.
2. Load `.env` only in local dev (`python-dotenv`).
3. In CI / cloud, inject via the platform's secrets store (GitHub Actions secrets, Azure Key Vault, AWS Secrets Manager, GCP Secret Manager).
