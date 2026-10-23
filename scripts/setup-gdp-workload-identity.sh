#!/bin/bash
# Wires up gdp-service's storage access via GKE Workload Identity instead of
# a service-account key file: creates the tables bucket, a dedicated GCP
# service account (GSA) with access to that bucket ONLY, a Kubernetes
# ServiceAccount (KSA) in the target namespace, and the IAM binding and
# annotation that make GKE's metadata server serve the GSA's credentials to
# pods running as the KSA. gdp-service/deployment.yaml then just sets
# serviceAccountName - gdp-table-repo's storage.Client() picks the
# credentials up via Application Default Credentials, no code changes.
#
# Tables (<owner>/<name>.sdml) and their permission records (.perm) both
# live in the one bucket, so objectAdmin on it is all the GSA needs - no
# project-wide roles, no Datastore.
#
# Requires: the GKE cluster already has Workload Identity enabled (see
# setup-workload-identity.sh), and kubectl pointed at that cluster.
#
# Idempotent - safe to re-run.
#
# Usage: ./scripts/setup-gdp-workload-identity.sh <project> [namespace] [bucket] [location] [gsa-name] [ksa-name]
# Defaults: namespace=jupyter-ai, bucket=bearborg-gdp-tables, location=us-west2,
#           gsa-name=gdp-service, ksa-name=gdp-service
set -euo pipefail

PROJECT_ID="${1:?usage: $0 <gcp-project> [namespace] [bucket] [location] [gsa-name] [ksa-name]}"
NAMESPACE="${2:-jupyter-ai}"
BUCKET="${3:-bearborg-gdp-tables}"
LOCATION="${4:-us-west2}"
GSA_NAME="${5:-gdp-service}"
KSA_NAME="${6:-gdp-service}"
GSA_EMAIL="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Bucket: private (uniform access, public access prevention enforced).
if ! gcloud storage buckets describe "gs://${BUCKET}" --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${BUCKET}" \
    --project "$PROJECT_ID" \
    --location "$LOCATION" \
    --uniform-bucket-level-access \
    --public-access-prevention
fi

# GSA: create if needed, then grant access to this bucket only.
if ! gcloud iam service-accounts describe "$GSA_EMAIL" --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$GSA_NAME" \
    --project "$PROJECT_ID" \
    --display-name="Global Data Plane service (gdp-service) bucket access"
fi

gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member="serviceAccount:${GSA_EMAIL}" \
  --role="roles/storage.objectAdmin"

# KSA: create in-cluster, bind it to the GSA, annotate so the metadata
# server recognizes it.
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

echo "Done. gdp-service/deployment.yaml should use serviceAccountName=$KSA_NAME and BUCKET_NAME=$BUCKET."
