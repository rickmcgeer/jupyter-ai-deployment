#!/bin/bash
# Runs the BearBorg JupyterLab image (rickmcgeer/jupyter-ai-image) on Berkeley
# Savio under Apptainer. Run it on a COMPUTE node (inside salloc/srun/sbatch),
# not on a login node.
#
# What Kubernetes/the Hub did for the pod and Apptainer doesn't:
#   - environment: the persona name/models and Vertex AI project, passed below
#   - startup hooks: `apptainer exec` ignores the image's entrypoint, so the
#     docker-stacks before-notebook.d hooks don't run on their own; we run the two
#     that matter (default-model seeding, persona settings title) ourselves
#   - writable paths: the image is read-only; --writable-tmpfs gives a throwaway
#     in-memory overlay so hooks that touch /opt/conda don't crash. User state
#     (~/.local, ~/.jupyter) goes to your real home, which Apptainer mounts.
#
# UNTESTED on Savio: written without access to Savio - see the checklist in the
# message that came with it. Module names and the login host are from memory.
#
# Usage: ./run-jupyter-ai.sh            (starts JupyterLab on $PORT, default 8888)
#        IMAGE_TAG=<tag> PORT=8890 ./run-jupyter-ai.sh
#
# Under Open OnDemand the batch-connect app (ood-app/) sets, for the proxy:
#   PORT       the port OOD picked
#   BASE_URL   /node/<host>/<port>/  (Lab must serve under the proxy's path)
#   JUPYTER_TOKEN  the one-time password OOD hands the Connect button
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-hub-services-20261023-143101}"
PORT="${PORT:-8888}"
BASE_URL="${BASE_URL:-/}"
SCRATCH_DIR="${SCRATCH:-/global/scratch/users/$USER}"
SIF="${SIF:-$SCRATCH_DIR/jupyter-ai-image-$IMAGE_TAG.sif}"

# Apptainer was called Singularity until 2021; Savio may expose either module.
if ! command -v apptainer >/dev/null 2>&1; then
  module load apptainer 2>/dev/null || module load singularity 2>/dev/null || true
fi
APPTAINER="$(command -v apptainer || command -v singularity || true)"
[ -n "$APPTAINER" ] || { echo "error: no apptainer/singularity - try 'module avail apptainer'" >&2; exit 1; }

# One-time image pull (~1.3 GB). Keep the cache off $HOME (quota) and /tmp.
if [ ! -f "$SIF" ]; then
  mkdir -p "$SCRATCH_DIR"
  export APPTAINER_CACHEDIR="$SCRATCH_DIR/.apptainer-cache" SINGULARITY_CACHEDIR="$SCRATCH_DIR/.apptainer-cache"
  echo "pulling rickmcgeer/jupyter-ai-image:$IMAGE_TAG to $SIF ..."
  "$APPTAINER" pull "$SIF" "docker://rickmcgeer/jupyter-ai-image:$IMAGE_TAG"
fi
if [ "${PULL_ONLY:-0}" = "1" ]; then
  echo "image ready: $SIF"
  exit 0
fi

# The chat features call Vertex AI; some HPC compute nodes have no outbound
# internet. Warn loudly rather than fail - the notebook itself works regardless.
if ! curl -s -m 8 -o /dev/null https://us-central1-aiplatform.googleapis.com/ 2>/dev/null; then
  echo "WARNING: this node can't reach Google APIs (us-central1-aiplatform.googleapis.com)." >&2
  echo "         JupyterLab will work, but Jupyter AI chat / Gemini won't." >&2
fi

# Same settings the BearBorg Hub gives its single-user pods
# (jupyter-ai-deployment/jupyterhub-chart/values-template.yaml, singleuser.extraEnv).
export APPTAINERENV_GOOGLE_CLOUD_PROJECT="civil-pattern-439416-k1"
export APPTAINERENV_VERTEXAI_PROJECT="civil-pattern-439416-k1"
export APPTAINERENV_VERTEXAI_LOCATION="us-central1"
export APPTAINERENV_GALYLEO_PERSONA_NAME="BearBorg"
export APPTAINERENV_GALYLEO_PERSONA_AVATAR="bearborg.png"
export APPTAINERENV_GALYLEO_MODELS="vertex_ai/gemini-2.5-flash:Gemini 2.5 Flash,vertex_ai/gemini-2.5-pro:Gemini 2.5 Pro"
export APPTAINERENV_GALYLEO_DEFAULT_MODEL="vertex_ai/gemini-2.5-flash"

# Vertex AI credentials: on GKE these come from Workload Identity, which doesn't
# exist here. Google's client libraries look in ~/.config/gcloud/ (your home is
# mounted into the container), or at GOOGLE_APPLICATION_CREDENTIALS if you set it
# before running this.
[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ] && export APPTAINERENV_GOOGLE_APPLICATION_CREDENTIALS="$GOOGLE_APPLICATION_CREDENTIALS"

# A fixed token (set by OOD) instead of a random one Jupyter would print.
[ -n "${JUPYTER_TOKEN:-}" ] && export APPTAINERENV_JUPYTER_TOKEN="$JUPYTER_TOKEN"

if [ "$BASE_URL" = "/" ]; then
  echo
  echo "On your laptop, tunnel in with:"
  echo "  ssh -L $PORT:$(hostname):$PORT $USER@hpc.brc.berkeley.edu"
  echo "then open the http://127.0.0.1:$PORT/lab?token=... URL JupyterLab prints below."
  echo
fi

# Behind Open OnDemand's proxy the browser's Origin (https://ood.brc.berkeley.edu)
# differs from the Host the server sees (<node>:<port>), so Jupyter blocks every
# cookie-authenticated API call and websocket as "Cross Origin" - terminals hang and
# kernels never connect. Trust exactly the OOD origin (anchored regex, so lookalikes
# like ood.brc.berkeley.edu.evil.example.com stay blocked). Only when proxied.
OOD_ORIGIN_PAT="${OOD_ORIGIN_PAT:-^https://ood[.]brc[.]berkeley[.]edu\$}"
ALLOW_ORIGIN_PAT=""
[ "$BASE_URL" != "/" ] && ALLOW_ORIGIN_PAT="$OOD_ORIGIN_PAT"

# Values go in as positional arguments ($1 $2 $3), not spliced into the script text.
exec "$APPTAINER" exec --cleanenv --writable-tmpfs "$SIF" bash -c '
  for hook in /usr/local/bin/before-notebook.d/10-jupyter-ai-defaults.py \
              /usr/local/bin/before-notebook.d/12-galyleo-persona-settings-schema.py; do
    "$hook" || echo "note: $hook failed (continuing)"
  done
  exec jupyter lab --no-browser --ip=0.0.0.0 --port="$1" \
       --ServerApp.base_url="$2" --ServerApp.allow_origin_pat="$3" \
       --ServerApp.root_dir="$HOME"
' _ "$PORT" "$BASE_URL" "$ALLOW_ORIGIN_PAT"
