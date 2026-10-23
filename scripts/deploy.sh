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

# Sourced for HUB_URL/GOOGLE_CLOUD_PROJECT/GDP_API_TOKEN, needed below to
# render gdp-service's manifests. Positional args still win over whatever
# this sets for RELEASE/NAMESPACE, so existing invocations are unaffected.
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../jupyterhub-chart/setup-env.sh}"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

RELEASE="${1:-jupyter-ai-1}"
NAMESPACE="${2:-${NAMESPACE:-jupyter-ai}}"
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

# gdp-service (the Global Data Plane sidecar) isn't part of the Helm
# release - deployed separately via kubectl, same as galyleo-service is
# for galyleo-beta. See gdp-service/deployment.yaml for why.
deploy_yaml() {
  local template="$1"
  envsubst < "$template" | kubectl apply -n "$NAMESPACE" -f -
}

echo "Deploying gdp-service..."
deploy_yaml "$SCRIPT_DIR/../gdp-service/deployment.yaml"
deploy_yaml "$SCRIPT_DIR/../gdp-service/service.yaml"
