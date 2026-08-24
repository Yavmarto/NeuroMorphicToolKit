#!/usr/bin/env bash
# ============================================================================
#  HISTORY PURGE — DESTRUCTIVE. Read the whole file before running.
#
#  PRECONDITIONS (do these first, in this order):
#    1. ROTATE the credentials. Scrubbing history does NOT protect a password
#       that is still valid. GitHub already has these commits on its servers.
#         - GRAFANA_ADMIN_PASSWORD  (see .env)
#         - the two values in .nmtk/deployment_secrets.json
#    2. Confirm you accept a FORCE-PUSH over every branch of every repo.
#       Anyone else with a clone must re-clone afterwards.
#    3. Backup exists at ~/nmtk-backup-2026-08-24  (mirror clones, 7 repos).
#
#  This script rewrites history in a FRESH CLONE, leaving your working copy
#  untouched until you deliberately push. Nothing is pushed automatically.
# ============================================================================
set -euo pipefail

SRC="/Users/yoshimartodihardjo/NeuroMorphicToolKit"
WORK="$HOME/nmtk-scrub-$(date +%Y%m%d-%H%M%S)"
FR="$HOME/.local/bin/git-filter-repo"

# Paths purged from ALL history. Uncomment the last line to also remove your
# private task notes (140 files, includes salary and IP analysis — see §12.6).
PURGE=(
  --path .env
  --path .nmtk/deployment_secrets.json
  # --path "current tasks"
)

echo ">>> workspace: $WORK"
mkdir -p "$WORK" && cd "$WORK"

for R in NeuroMorphicToolKit Neurobench Neurochip Neurohub Neurosense Neurosim neurocnl; do
  if [ "$R" = "NeuroMorphicToolKit" ]; then SUB="$SRC"; else SUB="$SRC/$R"; fi
  echo
  echo "=================== $R ==================="
  git clone --no-local "$SUB" "$R" -q
  cd "$R"
  cp "$SUB/.mailmap" ./.mailmap.fr 2>/dev/null || true

  # rewrite: drop secret paths, rewrite author/committer identities
  "$FR" "${PURGE[@]}" --invert-paths --mailmap .mailmap.fr --force
  rm -f .mailmap.fr

  echo "--- verification for $R ---"
  echo -n "  secret paths remaining: "
  git log --all --pretty=format: --name-only --diff-filter=A | sort -u \
    | grep -Ex '\.env|\.nmtk/deployment_secrets\.json' | wc -l | tr -d ' '
  echo -n "  response.nl addresses remaining: "
  git log --all --format='%ae%n%ce' | sort -u | grep -c 'response\.nl' || true
  cd ..
done

cat <<'MSG'

============================================================================
 REWRITE COMPLETE — NOTHING HAS BEEN PUSHED.
============================================================================
Inspect the rewritten repos in the workspace printed above. When satisfied,
push each one. filter-repo removes the 'origin' remote on purpose, so you
must re-add it, then force-push every branch and tag:

    cd <workspace>/<repo>
    git remote add origin <the original URL>
    git push --force --all origin
    git push --force --tags origin

Then, on GitHub for each repository:
  - Settings -> delete any stale branches you do not intend to publish
  - Ask GitHub Support to garbage-collect unreachable objects, or accept that
    old commits stay reachable by SHA for a while. This is exactly why
    rotation, not scrubbing, is what protects you.

Finally, in your working copy: re-clone from the rewritten remote. Do NOT
merge your old local clone back in — it still contains the old history and
would reintroduce everything.
============================================================================
MSG
