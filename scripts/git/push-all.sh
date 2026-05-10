#!/usr/bin/env bash
# push-all.sh — Stage, commit, and push changes in all top-level repos and the root repo.
# Usage: push-all.sh [commit message] [branch]
#   commit message  — quoted message (default: prompt user)
#   branch          — branch to push to (default: current branch, except main)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/repo_helpers.sh"

CURRENT_BRANCH="$(git -C "$ROOT_DIR" branch --show-current 2>/dev/null || true)"

if [[ -z "$CURRENT_BRANCH" ]]; then
  echo "Error: could not determine the current branch. Specify one explicitly."
  echo "Usage: push-all.sh [commit message] [branch]"
  exit 1
fi

if [[ $# -eq 0 ]]; then
  echo -n "Enter commit message [chore: update]: "
  read -r MESSAGE
  MESSAGE="${MESSAGE:-chore: update}"
  BRANCH="$CURRENT_BRANCH"
else
  MESSAGE="$1"
  BRANCH="${2:-$CURRENT_BRANCH}"
fi

if [[ "$BRANCH" == "main" ]]; then
  echo "Error: push-all.sh will not run on 'main'. Use a non-main branch."
  exit 1
fi

push_repo() {
  local dir="$1"
  local name="$2"

  echo ""
  echo "──────────────────────────────────────────"
  echo "  Repo: $name"
  echo "──────────────────────────────────────────"

  cd "$dir"

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

  if [[ -n "$(git status --porcelain)" ]]; then
    echo "  Staging all changes..."
    git add -A

    echo "  Committing: \"$MESSAGE\""
    git commit -m "$MESSAGE"
  else
    echo "  Nothing to commit."
  fi

  echo "  Pushing to origin/$BRANCH..."
  git push origin "$BRANCH"

  cd "$ROOT_DIR"
}

echo "======================================================"
echo "  push-all.sh  |  branch: $BRANCH"
echo "======================================================"

while IFS=$'\t' read -r repo_name repo_dir; do
  push_repo "$repo_dir" "$repo_name"
done < <(list_managed_repos "$ROOT_DIR")

echo ""
echo "======================================================"
echo "  Done."
echo "======================================================"
