#!/usr/bin/env bash
# pull-all.sh — Pull latest changes in all submodules and the root repo.
# Usage: ./pull-all.sh [branch]
#   branch — branch to pull from (default: dev)

set -euo pipefail

BRANCH="${1:-dev}"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

pull_repo() {
  local dir="$1"
  local name="$2"

  echo ""
  echo "──────────────────────────────────────────"
  echo "  Repo: $name"
  echo "──────────────────────────────────────────"

  cd "$dir"

  # Make sure we're on the right branch (checkout if needed)
  local current_branch
  current_branch=$(git branch --show-current 2>/dev/null || echo "")

  if [[ "$current_branch" != "$BRANCH" ]]; then
    echo "  Switching from '$current_branch' to '$BRANCH'..."
    git checkout "$BRANCH" 2>&1 || {
      echo "  [SKIP] Branch '$BRANCH' does not exist in $name — skipping."
      cd "$ROOT_DIR"
      return 0
    }
  fi

  # Warn about uncommitted changes that could block the pull
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "  [WARN] Uncommitted changes detected in $name — stashing before pull..."
    git stash push -m "pull-all.sh auto-stash before pull"
    git pull --ff-only origin "$BRANCH"
    echo "  Restoring stash..."
    git stash pop
  else
    git pull --ff-only origin "$BRANCH"
  fi

  cd "$ROOT_DIR"
}

echo "======================================================"
echo "  pull-all.sh  |  branch: $BRANCH"
echo "======================================================"

# Sync submodule URL registrations
git submodule sync --recursive

# ── Submodules first (bottom-up) ────────────────────────
git submodule foreach --quiet 'echo $displaypath' | while read -r sub; do
  pull_repo "$ROOT_DIR/$sub" "$sub"
done

# ── Root repo last ──────────────────────────────────────
pull_repo "$ROOT_DIR" "(root)"

echo ""
echo "======================================================"
echo "  Done."
echo "======================================================"
