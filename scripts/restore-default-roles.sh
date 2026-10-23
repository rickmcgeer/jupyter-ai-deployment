#!/bin/bash
# One-time repair: re-grant the default `user` role to every Hub user that has
# lost it.
#
# Why this exists: the BearBorg Hub config used to give the `user` role
# `"users": ["*"]`. That is not a wildcard - the Hub looks up a user literally
# named "*" - and an explicit `users` list makes role membership an exact match,
# so every Hub restart REVOKED the role from every real user. They only got it
# back when they next logged in (the Hub grants it at login). Meanwhile a
# logged-in user with no role has no scopes at all (can't reach their server),
# and their server's token - capped by the owner's scopes - can't report
# activity either. The config is fixed (no `users` key on that role); this
# repairs the memberships it already wiped. Safe to re-run.
#
# Uses the Hub's own roles.assign_default_roles(): grants `user` to every user
# (and keeps `admin` in sync with the admin flag). It only ADDS roles.
#
# Backs up the Hub DB (sqlite) in the pod first, and only if something needs
# changing. DRY_RUN=1 prints what would change and touches nothing.
#
# Requires kubectl pointed at the right cluster (for BearBorg:
# `gcloud config set account mcgeer@berkeley.edu` then
# `gcloud container clusters get-credentials jupyter-ai-cluster --zone us-west2-a --project civil-pattern-439416-k1`).
#
# Usage: [DRY_RUN=1] ./scripts/restore-default-roles.sh [namespace]
# Defaults: namespace=jupyter-ai
set -euo pipefail

NAMESPACE="${1:-jupyter-ai}"
export DRY_RUN="${DRY_RUN:-0}"

HUBPOD="$(kubectl get pods -n "$NAMESPACE" -l component=hub -o jsonpath='{.items[0].metadata.name}')"
echo "hub pod: $HUBPOD   (DRY_RUN=$DRY_RUN)"

{
  python3 -c 'import os; print("DRY_RUN = %r" % (os.environ["DRY_RUN"] == "1"))'
  cat <<'PYEOF'
import shutil, time
from jupyterhub import orm, roles

src = "/srv/jupyterhub/jupyterhub.sqlite"
db = orm.new_session_factory("sqlite:///" + src)()

missing = [
    u for u in db.query(orm.User).order_by(orm.User.name)
    if "user" not in [r.name for r in u.roles]
]
if not missing:
    print("every user already has the `user` role - nothing to do")
    raise SystemExit(0)

print("%d user(s) missing the `user` role:" % len(missing))
for u in missing:
    print("  ", u.name, "| current roles:", sorted(r.name for r in u.roles))

if DRY_RUN:
    print("DRY_RUN: no changes made")
    raise SystemExit(0)

bak = src + ".bak-" + time.strftime("%Y%m%d-%H%M%S")
shutil.copy2(src, bak)
print("backup:", bak)

for u in missing:
    roles.assign_default_roles(db, entity=u)
db.commit()

still = [u.name for u in db.query(orm.User) if "user" not in [r.name for r in u.roles]]
print("granted. users still missing the role:", still)
PYEOF
} | kubectl exec -i -n "$NAMESPACE" "$HUBPOD" -c hub -- python -
