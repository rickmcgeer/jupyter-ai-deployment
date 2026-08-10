#!/bin/bash
# Usage: ./scripts/deploy.sh [release] [namespace] [values-file]
# Defaults: release=jupyter-ai-1, namespace=jupyter-ai, values-file=jupyterhub-chart/values.yaml
#
# release defaults to jupyter-ai-1 - the name of the EXISTING live release
# (see global-data-plane-hub repo) - deliberately, so this upgrades it in
# place rather than installing a second, colliding Hub in the same
# namespace. Only pass a different release name for a genuinely separate
# deployment (e.g. testing against a different cluster/namespace).
#
# CHART_VERSION defaults to 4.0.0 - the version the live release is
# currently on - so this migration doesn't also silently pull in an
# unrelated chart upgrade. Bump it deliberately, separately, once the
# architecture migration itself is verified working.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE="${1:-jupyter-ai-1}"
NAMESPACE="${2:-jupyter-ai}"
VALUES_FILE="${3:-$SCRIPT_DIR/../jupyterhub-chart/values.yaml}"
CHART_VERSION="${CHART_VERSION:-4.0.0}"

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "error: $VALUES_FILE not found - run jupyterhub-chart/prepare-values.sh first." >&2
  exit 1
fi

helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
helm repo update jupyterhub
helm upgrade --install "$RELEASE" jupyterhub/jupyterhub \
  --version "$CHART_VERSION" \
  --namespace="$NAMESPACE" --create-namespace \
  -f "$VALUES_FILE"
