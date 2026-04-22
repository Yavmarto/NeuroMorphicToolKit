#!/usr/bin/env bash
# create-pr.sh — Open pull requests via gh CLI in all submodules and the root repo.
# Usage: create-pr.sh [title] [base-branch]
#   title        — PR title (prompted if not supplied)
#   base-branch  — target branch to merge into (default: main)
#
# Requires the GitHub CLI (gh). Install: https://cli.github.com/
# Authenticate first: gh auth login

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v gh &>/dev/null; then
  echo "Error: 'gh' (GitHub CLI) is required. Install from https://cli.github.com/"
  exit 1
fi

gh auth status &>/dev/null || {
  echo "Error: not authenticated with GitHub CLI. Run 'gh auth login' first."
  exit 1
}

if [[ $# -eq 0 ]]; then
  echo -n "Enter PR title [chore: update]: "
  read -r TITLE
  TITLE="${TITLE:-chore: update}"
  BASE_BRANCH="main"
else
  TITLE="$1"
  BASE_BRANCH="${2:-main}"
fi

create_pr_in() {
  local dir="$1"
  local name="$2"

  echo ""
  echo "──────────────────────────────────────────"
  echo "  Repo: $name"
  echo "──────────────────────────────────────────"

  cd "$dir"

  local current_branch
  current_branch=$(git branch --show-current 2>/dev/null || echo "")

  if [[ -z "$current_branch" ]]; then
    echo "  [SKIP] Detached HEAD — skipping."
    cd "$ROOT_DIR"
    return 0
  fi

  if [[ "$current_branch" == "$BASE_BRANCH" ]]; then
    echo "  [SKIP] Already on '$BASE_BRANCH' — nothing to PR."
    cd "$ROOT_DIR"
    return 0
  fi

  # Ensure the remote base ref is up to date before counting commits
  git fetch origin "$BASE_BRANCH" &>/dev/null 2>&1 || true

  local ahead
  ahead=$(git rev-list --count "origin/$BASE_BRANCH..HEAD" 2>/dev/null || echo "0")
  if [[ "$ahead" == "0" ]]; then
    echo "  [SKIP] No commits ahead of '$BASE_BRANCH'."
    cd "$ROOT_DIR"
    return 0
  fi

  echo "  Pushing '$current_branch' to origin..."
  git push --set-upstream origin "$current_branch" 2>&1 || \
    echo "  [WARN] Push failed — PR creation may not succeed."

  local existing
  existing=$(gh pr list \
    --head "$current_branch" \
    --base "$BASE_BRANCH" \
    --json url \
    --jq '.[0].url' 2>/dev/null || true)

  if [[ -n "$existing" ]]; then
    echo "  [INFO] PR already exists: $existing"
    cd "$ROOT_DIR"
    return 0
  fi

  local body
  body=$(git log "origin/$BASE_BRANCH..HEAD" --oneline --no-merges 2>/dev/null \
    | head -20 | sed 's/^/- /' || true)
  [[ -z "$body" ]] && body="Automated PR via create-pr.sh"

  echo "  Creating PR: '$TITLE' ($current_branch → $BASE_BRANCH)..."
  gh pr create \
    --title "$TITLE" \
    --base "$BASE_BRANCH" \
    --head "$current_branch" \
    --body "$body" \
    && echo "  [OK]" \
    || echo "  [WARN] gh pr create failed — check repo permissions and remote."

  cd "$ROOT_DIR"
}

echo "======================================================"
echo "  create-pr.sh  |  base: $BASE_BRANCH"
echo "======================================================"

git submodule foreach --quiet 'echo $displaypath' | while read -r sub; do
  create_pr_in "$ROOT_DIR/$sub" "$sub"
done

create_pr_in "$ROOT_DIR" "(root)"

echo ""
echo "======================================================"
echo "  Done."
echo "======================================================"
