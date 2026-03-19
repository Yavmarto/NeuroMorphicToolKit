#!/usr/bin/env bash
# push-all.sh — Stage, commit, and push changes in all submodules and the root repo.
# Usage: ./push-all.sh [branch] [commit message]
#   branch          — branch to push to (default: dev)
#   commit message  — quoted message (default: "chore: update")

set -euo pipefail

BRANCH="${1:-dev}"
MESSAGE="${2:-chore: update}"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

push_repo() {
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

  # Stage all changes
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "  Staging all changes..."
    git add -A

    echo "  Committing: \"$MESSAGE\""
    git commit -m "$MESSAGE"
  else
    echo "  Nothing to commit."
  fi

  # Push
  echo "  Pushing to origin/$BRANCH..."
  git push origin "$BRANCH"

  cd "$ROOT_DIR"
}

echo "======================================================"
echo "  push-all.sh  |  branch: $BRANCH"
echo "======================================================"

# ── Submodules ──────────────────────────────────────────
git submodule foreach --quiet 'echo $displaypath' | while read -r sub; do
  push_repo "$ROOT_DIR/$sub" "$sub"
done

# ── Root repo ───────────────────────────────────────────
push_repo "$ROOT_DIR" "(root)"

echo ""
echo "======================================================"
echo "  Done."
echo "======================================================"
