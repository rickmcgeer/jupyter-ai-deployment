# Running the BearBorg notebook image on Berkeley Savio

The same image the BearBorg Hub runs (`rickmcgeer/jupyter-ai-image`), run under
Apptainer on a Savio compute node, launched from Open OnDemand.

**UNTESTED on Savio** - written without cluster access. Module names, the login
host, and the `/node/<host>/<port>/` proxy path are from memory; check them against
the BRC docs.

- `run-jupyter-ai.sh` - pulls the image (once, to scratch) and runs JupyterLab under
  `apptainer exec`. Works standalone (prints an SSH tunnel command) or under OOD
  (`PORT`, `BASE_URL`, `JUPYTER_TOKEN`). `PULL_ONLY=1` just pulls the image.
- `ood-app/bearborg-jupyterlab/` - an Open OnDemand batch-connect "sandbox app".

## Install (from an OOD shell on Savio)

```bash
git clone https://github.com/rickmcgeer/jupyter-ai-deployment.git ~/jupyter-ai-deployment
mkdir -p ~/bearborg ~/ondemand/dev
cp ~/jupyter-ai-deployment/savio/run-jupyter-ai.sh ~/bearborg/
cp -r ~/jupyter-ai-deployment/savio/ood-app/bearborg-jupyterlab ~/ondemand/dev/
```

Edit `~/ondemand/dev/bearborg-jupyterlab/form.yml` and set `cluster:` to your
cluster's OOD id. Then in OOD: **Develop -> My Sandbox Apps (Development)** ->
BearBorg JupyterLab.

## Vertex AI credentials

On GKE the image gets these from Workload Identity, which doesn't exist on Savio.
Google's client libraries look in `~/.config/gcloud/` (home is mounted into the
container) or at `GOOGLE_APPLICATION_CREDENTIALS`. Without credentials JupyterLab
works but Jupyter AI chat doesn't.

## What doesn't carry over

There is no Hub here, so the Hub Services tiles and the `gdp` service are inert.
The persona's Settings title may stay "Galyleo AI": the hook that renames it
writes into the read-only image and fails harmlessly.
