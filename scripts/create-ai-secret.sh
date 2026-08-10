#!/bin/bash
# Creates the Kubernetes Secret that backs the builtin Vertex AI key -
# a GCP service-account key with Vertex AI access, mounted into every
# singleuser pod at /etc/ai-key/key.json (see jupyterhub-chart/values-template.yaml).
#
# Usage: ./scripts/create-ai-secret.sh [namespace] [secret-name]
# Defaults: namespace=jupyter-ai, secret-name=jupyter-ai-key
set -euo pipefail

NAMESPACE="${1:-jupyter-ai}"
SECRET_NAME="${2:-jupyter-ai-key}"
KEY_FILE="$(dirname "${BASH_SOURCE[0]}")/../config/ai-key.json"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "error: $KEY_FILE not found." >&2
  echo "Create a GCP service-account key with Vertex AI User access and save it there first:" >&2
  echo "  gcloud iam service-accounts keys create $KEY_FILE --iam-account=<sa-name>@<project>.iam.gserviceaccount.com" >&2
  exit 1
fi

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic "$SECRET_NAME" \
  --from-file=key.json="$KEY_FILE" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Applied secret $SECRET_NAME in namespace $NAMESPACE"
