#!/usr/bin/env bash
# create-branch.sh — Create and track a new branch across all submodules and root repo.
# Usage: create-branch.sh <new-branch> [base-branch]
#   new-branch   — name of the branch to create
#   base-branch  — branch to base off (default: current branch in each repo)

set -euo pipefail

NEW_BRANCH="${1:?Usage: create-branch.sh <new-branch> [base-branch]}"
BASE_BRANCH="${2:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

create_branch_in() {
  local dir="$1"
  local name="$2"

  echo ""
  echo "──────────────────────────────────────────"
  echo "  Repo: $name"
  echo "──────────────────────────────────────────"

  cd "$dir"

  if [[ -n "$BASE_BRANCH" ]]; then
    local current
    current=$(git branch --show-current 2>/dev/null || echo "")
    if [[ "$current" != "$BASE_BRANCH" ]]; then
      echo "  Switching to base '$BASE_BRANCH'..."
      git checkout "$BASE_BRANCH" 2>&1 || {
        echo "  [SKIP] Base '$BASE_BRANCH' not found in $name — skipping."
        cd "$ROOT_DIR"
        return 0
      }
    fi
  fi

  if git show-ref --verify --quiet "refs/heads/$NEW_BRANCH" 2>/dev/null; then
    echo "  [INFO] Branch '$NEW_BRANCH' already exists — checking out."
    git checkout "$NEW_BRANCH"
  else
    local from
    from=$(git branch --show-current 2>/dev/null || echo "HEAD")
    echo "  Creating '$NEW_BRANCH' from '$from'..."
    git checkout -b "$NEW_BRANCH"
    git push --set-upstream origin "$NEW_BRANCH" 2>&1 || \
      echo "  [WARN] Push to origin failed — branch created locally only."
  fi

  cd "$ROOT_DIR"
}

echo "======================================================"
echo "  create-branch.sh  |  branch: $NEW_BRANCH${BASE_BRANCH:+  |  base: $BASE_BRANCH}"
echo "======================================================"

git submodule foreach --quiet 'echo $displaypath' | while read -r sub; do
  create_branch_in "$ROOT_DIR/$sub" "$sub"
done

create_branch_in "$ROOT_DIR" "(root)"

echo ""
echo "======================================================"
echo "  Done. Branch '$NEW_BRANCH' created across all repos."
echo "======================================================"
