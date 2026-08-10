#!/bin/bash
# Usage: ./scripts/deploy.sh [namespace] [values-file]
# Defaults: namespace=jupyter-ai, values-file=jupyterhub-chart/values.yaml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${1:-jupyter-ai}"
VALUES_FILE="${2:-$SCRIPT_DIR/../jupyterhub-chart/values.yaml}"

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "error: $VALUES_FILE not found - run jupyterhub-chart/prepare-values.sh first." >&2
  exit 1
fi

helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
helm repo update jupyterhub
helm upgrade --install jupyter-ai jupyterhub/jupyterhub \
  --namespace="$NAMESPACE" --create-namespace \
  -f "$VALUES_FILE"
