#!/bin/bash
# Wires up the builtin Vertex AI access via GKE Workload Identity instead of
# a downloaded service-account key: creates the GCP service account (GSA)
# and grants it Vertex AI access, creates a Kubernetes ServiceAccount (KSA)
# in the target namespace, binds the two together via IAM, and annotates the
# KSA so GKE's metadata server serves the GSA's credentials to any pod that
# runs as it. jupyterhub-chart/values-template.yaml then just points
# singleuser.serviceAccountName at the KSA - no key file, nothing to mount
# or rotate.
#
# Requires: the GKE cluster already has Workload Identity enabled
# (`--workload-pool=<project>.svc.id.goog` at creation, or added after via
# `gcloud container clusters update <cluster> --workload-pool=<project>.svc.id.goog`).
#
# Usage: ./scripts/setup-workload-identity.sh [project] [namespace] [gsa-name] [ksa-name]
# Defaults: namespace=jupyter-ai, gsa-name=jupyter-ai-vertex, ksa-name=jupyter-ai-vertex
set -euo pipefail

PROJECT_ID="${1:?usage: $0 <gcp-project> [namespace] [gsa-name] [ksa-name]}"
NAMESPACE="${2:-jupyter-ai}"
GSA_NAME="${3:-jupyter-ai-vertex}"
KSA_NAME="${4:-jupyter-ai-vertex}"
GSA_EMAIL="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# GSA: create if it doesn't already exist, then grant Vertex AI access.
if ! gcloud iam service-accounts describe "$GSA_EMAIL" --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$GSA_NAME" \
    --project "$PROJECT_ID" \
    --display-name="Jupyter AI builtin Vertex AI access"
fi

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${GSA_EMAIL}" \
  --role="roles/aiplatform.user" \
  --condition=None

# KSA: create in-cluster, bind it to the GSA, annotate so the metadata
# server recognizes it.
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl create serviceaccount "$KSA_NAME" \
  --namespace "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" \
  --project "$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]"

kubectl annotate serviceaccount "$KSA_NAME" \
  --namespace "$NAMESPACE" \
  "iam.gke.io/gcp-service-account=${GSA_EMAIL}" \
  --overwrite

echo "Done. Set JUPYTER_KSA=$KSA_NAME (namespace $NAMESPACE) in setup-env.sh."
