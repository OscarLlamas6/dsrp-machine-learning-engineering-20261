# syntax=docker/dockerfile:1.7
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    AZURE_STORAGE_ACCOUNT=$AZURE_STORAGE_ACCOUNT \
    AZURE_STORAGE_CONTAINER=$AZURE_STORAGE_CONTAINER \
    AZURE_STORAGE_CONNECTION_STRING=$AZURE_STORAGE_CONNECTION_STRING


WORKDIR /app

# Install dependencies first (better layer caching)
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY train.py ./


ENTRYPOINT ["python", "-u", "train.py"]
