#!/bin/bash
# Revokes a stale token of a JupyterHub-registered service.
#
# Why this exists: changing a service's `api_token` in the Hub config (e.g.
# gdp-service-config in values-template.yaml) only ADDS the new token -
# JupyterHub keeps every token it has already registered in its database, so
# the old value keeps authenticating as the service until it's deleted.
# There's no REST endpoint for service tokens, so this edits the Hub's
# sqlite DB through JupyterHub's own ORM, inside the running hub pod.
#
# Safety: copies the DB file aside first, and aborts unless the old token
# resolves to exactly the named service. Deletes only that one token row.
#
# The old token is read from the OLD_TOKEN environment variable and sent to
# the pod over stdin only - never as a command-line argument, so it doesn't
# appear in `ps` locally or in the pod.
#
# Requires kubectl pointed at the right cluster (for BearBorg:
# `gcloud config set account mcgeer@berkeley.edu` then
# `gcloud container clusters get-credentials jupyter-ai-cluster --zone us-west2-a --project civil-pattern-439416-k1`).
#
# Usage: OLD_TOKEN=<stale token> ./scripts/revoke-service-token.sh <service> [namespace]
# Defaults: namespace=jupyter-ai
set -euo pipefail

SERVICE="${1:?usage: OLD_TOKEN=<token> $0 <service-name> [namespace]}"
NAMESPACE="${2:-jupyter-ai}"
: "${OLD_TOKEN:?set OLD_TOKEN to the stale token value}"
export SERVICE

HUBPOD="$(kubectl get pods -n "$NAMESPACE" -l component=hub -o jsonpath='{.items[0].metadata.name}')"
echo "hub pod: $HUBPOD"

{
  # First line of the script carries the two values, safely quoted by repr().
  python3 -c 'import os; print("SERVICE, OLD_TOKEN = %r, %r" % (os.environ["SERVICE"], os.environ["OLD_TOKEN"]))'
  cat <<'PYEOF'
import shutil, time
from jupyterhub import orm

src = "/srv/jupyterhub/jupyterhub.sqlite"

bak = src + ".bak-" + time.strftime("%Y%m%d-%H%M%S")
shutil.copy2(src, bak)
print("backup:", bak)

db = orm.new_session_factory("sqlite:///" + src)()
tok = orm.APIToken.find(db, OLD_TOKEN)
if tok is None:
    raise SystemExit("old token does not match any registered token - nothing to do")
if tok.service is None or tok.service.name != SERVICE:
    raise SystemExit("token does not belong to service %r - aborting" % SERVICE)

print("deleting token id %s (prefix %s) of service %r" % (tok.id, tok.prefix, SERVICE))
db.delete(tok)
db.commit()

svc = db.query(orm.Service).filter_by(name=SERVICE).one()
print("remaining tokens:", [(t.id, t.prefix) for t in svc.api_tokens])
PYEOF
} | kubectl exec -i -n "$NAMESPACE" "$HUBPOD" -c hub -- python -
