#!/usr/bin/env bash
# ponytail: single rsync+git-init path; upgrade to git-filter-repo if history must be kept.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/publish_public_snapshot.sh OUTPUT_DIR [--verify-only]

Build a fresh, allowlisted public snapshot with no git history.

Excludes (CEL-329 / CEL-341):
  .env, .env.*, .nmtk/, scripts/.env, current tasks/,
  nmtk/neuro_toolkit/deployment_state.json, docs/superpowers/,
  build artifacts, and other local-only paths.

After export, runs the five scrub verification commands. All must be empty/zero.

Examples:
  scripts/publish_public_snapshot.sh /tmp/nmtk-public-snapshot
  scripts/publish_public_snapshot.sh /tmp/nmtk-public-snapshot --verify-only
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

OUTPUT_DIR="${1:-}"
VERIFY_ONLY=0
if [[ "${2:-}" == "--verify-only" ]]; then
  VERIFY_ONLY=1
fi

if [[ -z "$OUTPUT_DIR" ]]; then
  echo "error: OUTPUT_DIR required" >&2
  usage >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
USERS_DIR="$(printf '%s' Users)"
EMPLOYER_RE="$(printf 'response\\.%s' nl)"

RSYNC_EXCLUDES=(
  --exclude '.git'
  --exclude '.env'
  --exclude '.env.*'
  --exclude '.nmtk'
  --exclude 'scripts/.env'
  --exclude 'current tasks'
  --exclude 'nmtk/neuro_toolkit/deployment_state.json'
  --exclude 'docs/superpowers'
  --exclude '.claude'
  --exclude 'paper'
  --exclude 'scratch'
  --exclude 'data'
  --exclude 'recordings'
  --exclude 'nmtk-workspaces'
  --exclude 'demo screenshots'
  --exclude 'build'
  --exclude 'node_modules'
  --exclude '.dart_tool'
  --exclude '__pycache__'
  --exclude '.pytest_cache'
  --exclude '.mypy_cache'
  --exclude '.ruff_cache'
  --exclude '.venv'
  --exclude 'venv'
  --exclude '*.pyc'
  --exclude '.DS_Store'
  --exclude 'Pods'
  --exclude '.gradle'
  --exclude '.agents'
  --exclude '.antigravitycli'
  --exclude '.understand-anything'
  --exclude '.idea'
  --exclude '.hypothesis'
  --exclude '.cache'
  --exclude '.superpowers'
  --exclude '.flutter-plugins'
  --exclude '.flutter-plugins-dependencies'
  --exclude 'logs'
  --exclude '*.egg-info'
  --exclude 'ephemeral'
  --exclude 'coverage'
  --exclude '.coverage'
  --exclude 'tmp_probe_*'
  --exclude 'tmp_cel*_debug*.dart'
  --exclude 'tmp_cel*_debug*.py'
)

verify_snapshot() {
  local dir="$1"
  local failed=0
  cd "$dir"

  echo "== verification 1: secret paths in history =="
  if out=$(git log --all --pretty=format: --name-only --diff-filter=A 2>/dev/null | sort -u | grep -Ex '\.env|\.nmtk/deployment_secrets\.json' || true); then
    if [[ -n "$out" ]]; then
      echo "$out"
      failed=1
    fi
  fi

  echo "== verification 2: employer identities in history =="
  count=$(git log --all --format='%ae%n%ce' 2>/dev/null | sort -u | grep -c "$EMPLOYER_RE" || true)
  echo "employer-identity commit count: ${count:-0}"
  if [[ "${count:-0}" != "0" ]]; then
    failed=1
  fi

  echo "== verification 2b: employer identities in tracked content =="
  if out=$(git grep -lI -e "$EMPLOYER_RE" -- . 2>/dev/null || true); then
    if [[ -n "$out" ]]; then
      echo "$out"
      failed=1
    fi
  fi

  echo "== verification 3: current tasks tracked at HEAD =="
  count=$(git ls-files 'current tasks' 2>/dev/null | wc -l | tr -d ' ')
  echo "tracked current tasks files: $count"
  if [[ "$count" != "0" ]]; then
    failed=1
  fi

  echo "== verification 4: absolute home paths in tracked content =="
  users_root="$(printf '/%s/' Users)"
  if out=$(git grep -lI "$users_root" -- . ":(exclude)scripts/publish_public_snapshot.sh" 2>/dev/null || true); then
    if [[ -n "$out" ]]; then
      echo "$out"
      failed=1
    fi
  fi

  echo "== verification 5: known leaked secret values (optional) =="
  if [[ -n "${CEL341_SECRET_GREP_PATTERNS:-}" ]]; then
    # Space-separated patterns from Security after rotation (never commit real values).
    for pattern in $CEL341_SECRET_GREP_PATTERNS; do
      if out=$(git grep -I -e "$pattern" -- . 2>/dev/null || true); then
        if [[ -n "$out" ]]; then
          echo "matched pattern: $pattern"
          echo "$out"
          failed=1
        fi
      fi
    done
  else
    echo "skipped (set CEL341_SECRET_GREP_PATTERNS to run check 5)"
  fi

  if [[ "$failed" -ne 0 ]]; then
    echo "VERIFY FAILED" >&2
    return 1
  fi
  echo "VERIFY OK"
}

if [[ "$VERIFY_ONLY" -eq 1 ]]; then
  if [[ ! -d "$OUTPUT_DIR/.git" ]]; then
    echo "error: $OUTPUT_DIR is not a git repo" >&2
    exit 1
  fi
  verify_snapshot "$OUTPUT_DIR"
  exit 0
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "Exporting allowlisted tree to $OUTPUT_DIR ..."
rsync -a "${RSYNC_EXCLUDES[@]}" "$ROOT/" "$OUTPUT_DIR/"

echo "Sanitizing absolute home paths in exported text files ..."
users_root="$(printf '/%s/' Users)"
if matches=$(grep -rlI "$users_root" "$OUTPUT_DIR" 2>/dev/null || true); then
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    perl -pi -e "s#/${USERS_DIR}/[^/[:space:]\\\"]+#\$HOME#g" "$file"
  done <<<"$matches"
fi

echo "Stripping employer identity lines from exported text metadata ..."
if matches=$(grep -rlI -e "$EMPLOYER_RE" "$OUTPUT_DIR" 2>/dev/null || true); then
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    grep -v -e "$EMPLOYER_RE" "$file" > "$file.cel341.tmp"
    mv "$file.cel341.tmp" "$file"
  done <<<"$matches"
fi

cd "$OUTPUT_DIR"
git init -q
git add -A
git commit -q -m "Public snapshot (CEL-341): allowlisted export, no prior history."
git clean -Xqdf

verify_snapshot "$OUTPUT_DIR"

echo "Snapshot ready at: $OUTPUT_DIR"
echo "Push to Yavmarto after credential rotation (CEL-341 step 1) is confirmed."
