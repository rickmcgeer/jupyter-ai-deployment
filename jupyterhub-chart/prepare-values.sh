#!/bin/bash
set -euo pipefail
ENV_FILE="${1:-setup-env.sh}"
source "$ENV_FILE"
envsubst < values-template.yaml > values.yaml
echo "Wrote values.yaml from values-template.yaml + $ENV_FILE"
