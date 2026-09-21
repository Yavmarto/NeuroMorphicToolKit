#!/usr/bin/env bash
# CEL-459 / CEL-382 Phase 0 — expunge leaked secret files from NMTK git history.
#
# Removes these paths from every reachable ref (all branches and tags):
#   .env, .nmtk/deployment_secrets.json,
#   nmtk/neuro_toolkit/deployment_state.json, current tasks/
# and rewrites every non-public commit identity (employer and local-hostname
# addresses) to the public GitHub noreply address.
#
# This script NEVER pushes. It builds and verifies a rewritten mirror, then
# prints the force-push command for a human or DevOps to run in a maintenance
# window. Read the printed warning before pushing: every collaborator must
# re-clone afterwards.
#
# Requires git-filter-repo:
#   uv tool install git-filter-repo   # or: pipx install git-filter-repo
set -euo pipefail

ORIGIN_URL="${ORIGIN_URL:-https://github.com/Completed-Spoon-6/NeuroMorphicToolKit.git}"
WORKDIR="${WORKDIR:-${TMPDIR:-/tmp}/nmtk-history-scrub}"
PUBLIC_NAME="${PUBLIC_NAME:-Yoshikatsu Ashley Vaughn Martodihardjo}"
PUBLIC_EMAIL="${PUBLIC_EMAIL:-42234073+Yavmarto@users.noreply.github.com}"
MIRROR="$WORKDIR/nmtk-scrubbed.git"

usage() {
  cat <<'EOF'
Usage: scripts/scrub_git_history.sh

Environment:
  ORIGIN_URL     mirror source (default: private Completed-Spoon-6 origin)
  WORKDIR        scratch dir (default: $TMPDIR/nmtk-history-scrub)
  PUBLIC_NAME    canonical name for rewritten identities
  PUBLIC_EMAIL   canonical email for rewritten identities

The script prints the force-push command at the end and does not run it.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v git-filter-repo >/dev/null 2>&1; then
  echo "error: git-filter-repo not found. Install with 'uv tool install git-filter-repo'." >&2
  exit 1
fi

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

echo "== clone mirror: $ORIGIN_URL"
git clone --quiet --mirror "$ORIGIN_URL" "$MIRROR"

cd "$MIRROR"

echo "== build identity mailmap from current history (no literals committed)"
MAILMAP="$WORKDIR/mailmap.txt"
: > "$MAILMAP"
git log --all --format='%ae%n%ce' | sort -u | while IFS= read -r email; do
  [[ -n "$email" ]] || continue
  case "$email" in
    *noreply.github.com|*"[bot]"*) continue ;;
  esac
  printf '%s <%s> <%s>\n' "$PUBLIC_NAME" "$PUBLIC_EMAIL" "$email" >> "$MAILMAP"
done
echo "   mapped $(wc -l < "$MAILMAP" | tr -d ' ') non-public identities"

echo "== build path removal list"
PATHS="$WORKDIR/remove-paths.txt"
cat > "$PATHS" <<'PATHS_EOF'
literal:.env
literal:.nmtk/deployment_secrets.json
literal:nmtk/neuro_toolkit/deployment_state.json
literal:current tasks
PATHS_EOF

echo "== rewrite history"
git filter-repo --force --mailmap "$MAILMAP" --invert-paths --paths-from-file "$PATHS" >/dev/null

echo "== verify"
failed=0
if git log --all --pretty=format: --name-only --diff-filter=A | sort -u | grep -Ex '\.env|\.nmtk/deployment_secrets\.json'; then
  echo "FAIL: secret path still reachable" >&2; failed=1
fi
if git log --all --pretty=format: --name-only --diff-filter=A | sort -u | grep -E '^current tasks/'; then
  echo "FAIL: private notes still reachable" >&2; failed=1
fi
if git log --all --format='%ae%n%ce' | sort -u | grep -vE 'noreply\.github\.com|\[bot\]$' | grep -q .; then
  echo "FAIL: non-public identity still reachable" >&2
  git log --all --format='%ae%n%ce' | sort -u | grep -vE 'noreply\.github\.com|\[bot\]$' >&2
  failed=1
fi
if [[ "$failed" -ne 0 ]]; then
  echo "SCRUB VERIFY FAILED" >&2
  exit 1
fi

cat <<EOF

SCRUB VERIFY OK — rewritten mirror at: $MIRROR

Next step is destructive and must be coordinated with every repo user.
After branch protection is lifted and all users are asked to stop pushing:

  cd "$MIRROR"
  git push --force --mirror "$ORIGIN_URL"

Every existing clone and agent worktree must then re-clone. At least one
private credential in the removed history was rotated or waived in CEL-343,
so the removed values are inert; this rewrite is defense-in-depth.
EOF
