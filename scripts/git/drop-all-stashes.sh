#!/usr/bin/env bash
# drop-all-stashes.sh — Drop (clear) all stashes in all top-level repos and the root repo.
# Usage: drop-all-stashes.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/repo_helpers.sh"

drop_stashes_in_repo() {
  local dir="$1"
  local name="$2"

  echo ""
  echo "──────────────────────────────────────────"
  echo "  Repo: $name"
  echo "──────────────────────────────────────────"

  cd "$dir"
  
  local stashes
  stashes="$(git stash list 2>/dev/null || true)"

  if [[ -n "$stashes" ]]; then
    echo "  Found stashes in $name. Dropping..."
    git stash clear
    echo "  Done."
  else
    echo "  No stashes found in $name."
  fi

  cd "$ROOT_DIR"
}

echo "======================================================"
echo "  drop-all-stashes.sh"
echo "======================================================"

while IFS=$'\t' read -r repo_name repo_dir; do
  drop_stashes_in_repo "$repo_dir" "$repo_name"
done < <(list_managed_repos "$ROOT_DIR")

echo ""
echo "======================================================"
echo "  Done."
echo "======================================================"
