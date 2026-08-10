# jupyter-ai-deployment

JupyterHub-on-Kubernetes deployment for
[jupyter-ai-image](https://github.com/rickmcgeer/jupyter-ai-image), via the
upstream [zero-to-jupyterhub](https://z2jh.jupyter.org/) Helm chart. Same
pattern as `engageLively/coreshell-hub`'s `coreshell-drive-deployment`, pared
down to just what this deployment needs - no drive-service, no per-org
sidecar services.

## What this solves: the builtin Vertex AI access

`jupyter-ai-image` seeds every user's default Jupyter AI model to Gemini via
Vertex AI, but needs GCP credentials to actually call it. This uses **GKE
Workload Identity** rather than a downloaded service-account key: singleuser
pods run as a Kubernetes ServiceAccount (KSA) that's bound to a GCP service
account (GSA) via IAM, so GKE's metadata server hands out credentials to the
pod automatically. No key file to generate, store, mount, or ever rotate -
and no key sitting in a Secret that would need separate access control.

Requires the GKE cluster to have Workload Identity enabled already
(`--workload-pool=<project>.svc.id.goog` at cluster creation, or added
after the fact - see
[GKE's Workload Identity docs](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
if you're not sure whether this cluster has it).

```bash
./scripts/setup-workload-identity.sh "$GOOGLE_CLOUD_PROJECT"   # namespace/gsa/ksa names default to jupyter-ai / jupyter-ai-vertex
```

This creates the GSA (with `roles/aiplatform.user`), the KSA, the IAM
binding between them, and the annotation GKE's metadata server needs.
`values-template.yaml` then just points `singleuser.serviceAccountName` at
the KSA (set `JUPYTER_KSA` in `setup-env.sh` to match).

Users can still add their own key for a different provider through the AI
Settings UI in JupyterLab - this builtin access is a default, not the only
option.

## Deploy

```bash
./scripts/setup-workload-identity.sh "$GOOGLE_CLOUD_PROJECT"
cd jupyterhub-chart
cp setup-env.sh.sample setup-env.sh   # fill in OAuth client ID/secret, GCP project, hub URL, JUPYTER_KSA
./prepare-values.sh                   # renders values.yaml from values-template.yaml
cd ..
./scripts/deploy.sh
```

## Local testing

Workload Identity is GKE-only - there's no way to exercise the builtin
Vertex AI path on a local cluster (minikube, kind, Docker Desktop
Kubernetes). `values-local.yaml` skips that wiring entirely and is only
useful for checking the Hub/chart/image come up and the UI renders (no TLS,
dummy auth):

```bash
./scripts/deploy.sh jupyter-ai jupyterhub-chart/values-local.yaml
kubectl port-forward -n jupyter-ai svc/proxy-public 8080:80
```

Then open `http://localhost:8080` and log in with any username and the
password `dev` (see `DummyAuthenticator` in `values-local.yaml`). Add your
own provider key by hand through the AI Settings UI to test chat.
