#!/usr/bin/env bash
# pull-all.sh — Pull latest changes in all top-level repos and the root repo.
# Usage: pull-all.sh [branch]
#   branch — branch to pull from (default: current branch)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRANCH="${1:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/repo_helpers.sh"

pull_repo() {
  local dir="$1"
  local name="$2"

  echo ""
  echo "──────────────────────────────────────────"
  echo "  Repo: $name"
  echo "──────────────────────────────────────────"

  cd "$dir"

  local current_branch
  current_branch=$(git branch --show-current 2>/dev/null || echo "")

  local target_branch="${BRANCH:-$current_branch}"

  if [[ -z "$target_branch" ]]; then
    echo "  [SKIP] Not on any branch (detached HEAD?) in $name — skipping."
    cd "$ROOT_DIR"
    return 0
  fi

  if [[ -n "$BRANCH" && "$current_branch" != "$BRANCH" ]]; then
    echo "  Switching from '$current_branch' to '$BRANCH'..."
    git checkout "$BRANCH" 2>&1 || {
      echo "  [SKIP] Branch '$BRANCH' does not exist in $name — skipping."
      cd "$ROOT_DIR"
      return 0
    }
    target_branch="$BRANCH"
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    echo "  [WARN] Uncommitted changes in $name — stashing before pull..."
    git stash push -m "pull-all.sh auto-stash before pull"
    git pull --ff-only origin "$target_branch"
    echo "  Restoring stash..."
    git stash pop
  else
    git pull --ff-only origin "$target_branch"
  fi

  cd "$ROOT_DIR"
}

echo "======================================================"
echo "  pull-all.sh  |  branch: ${BRANCH:-current}"
echo "======================================================"

git submodule sync --recursive

while IFS=$'\t' read -r repo_name repo_dir; do
  pull_repo "$repo_dir" "$repo_name"
done < <(list_managed_repos "$ROOT_DIR")

echo ""
echo "======================================================"
echo "  Done."
echo "======================================================"
