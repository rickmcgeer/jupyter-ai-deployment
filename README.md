# jupyter-ai-deployment

JupyterHub-on-Kubernetes deployment for
[jupyter-ai-image](https://github.com/rickmcgeer/jupyter-ai-image), via the
upstream [zero-to-jupyterhub](https://z2jh.jupyter.org/) Helm chart. Same
pattern as `engageLively/coreshell-hub`'s `coreshell-drive-deployment`, pared
down to just what this deployment needs - no drive-service, no per-org
sidecar services.

## What this solves: the builtin Vertex AI key

`jupyter-ai-image` seeds every user's default Jupyter AI model to Gemini via
Vertex AI, but needs GCP credentials to actually call it. This repo
provisions those as a real Kubernetes Secret:

1. Create a GCP service account with Vertex AI User access, and a JSON key
   for it:
   ```bash
   gcloud iam service-accounts create jupyter-ai-vertex \
     --display-name="Jupyter AI builtin Vertex AI key"
   gcloud projects add-iam-policy-binding "$GOOGLE_CLOUD_PROJECT" \
     --member="serviceAccount:jupyter-ai-vertex@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com" \
     --role="roles/aiplatform.user"
   gcloud iam service-accounts keys create config/ai-key.json \
     --iam-account="jupyter-ai-vertex@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com"
   ```
2. Load it into the cluster as a Secret:
   ```bash
   ./scripts/create-ai-secret.sh          # namespace defaults to jupyter-ai
   ```
   `values-template.yaml` mounts this secret (`jupyter-ai-key`) at
   `/etc/ai-key` in every singleuser pod and points
   `GOOGLE_APPLICATION_CREDENTIALS` at it - matching exactly what
   `coreshell-hub`'s production Hub already does for its own `coreshell-ai-key`
   secret, just under a different secret name.

Users can still add their own key for a different provider through the AI
Settings UI in JupyterLab - this builtin key is a default, not the only
option.

## Deploy

```bash
cd jupyterhub-chart
cp setup-env.sh.sample setup-env.sh   # fill in OAuth client ID/secret, GCP project, hub URL
./prepare-values.sh                   # renders values.yaml from values-template.yaml
cd ..
./scripts/create-ai-secret.sh
./scripts/deploy.sh
```

## Local testing

For a local cluster (minikube, kind, Docker Desktop Kubernetes) with no TLS
and no Google OAuth:

```bash
./scripts/create-ai-secret.sh jupyter-ai jupyter-ai-key
./scripts/deploy.sh jupyter-ai jupyterhub-chart/values-local.yaml
kubectl port-forward -n jupyter-ai svc/proxy-public 8080:80
```

Then open `http://localhost:8080` and log in with any username and the
password `dev` (see `DummyAuthenticator` in `values-local.yaml`).
