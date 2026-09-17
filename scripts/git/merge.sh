#!/usr/bin/env bash
# merge.sh — Merge a source branch into the current branch across all submodules and root.
# Usage: merge.sh <source-branch> [--ours | --theirs | --abort | --no-ff]
#   source-branch  — branch to merge in
#   --ours         — auto-resolve conflicts keeping current branch's version
#   --theirs       — auto-resolve conflicts keeping source branch's version
#   --abort        — abort any in-progress merge across all repos
#   --no-ff        — force a merge commit even when fast-forward is possible

set -euo pipefail

SOURCE_BRANCH="${1:?Usage: merge.sh <source-branch> [--ours | --theirs | --abort | --no-ff]}"
STRATEGY="${2:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FAILED_LOG=$(mktemp)
trap 'rm -f "$FAILED_LOG"' EXIT

MERGE_FLAGS="--no-edit"
[[ "$STRATEGY" == "--no-ff" ]] && MERGE_FLAGS="$MERGE_FLAGS --no-ff"

merge_in() {
  local dir="$1"
  local name="$2"

  echo ""
  echo "──────────────────────────────────────────"
  echo "  Repo: $name"
  echo "──────────────────────────────────────────"

  cd "$dir"

  local current
  current=$(git branch --show-current 2>/dev/null || echo "")

  if [[ "$STRATEGY" == "--abort" ]]; then
    if git merge --abort 2>/dev/null; then
      echo "  [OK] Merge aborted."
    else
      echo "  [INFO] No merge in progress."
    fi
    cd "$ROOT_DIR"
    return 0
  fi

  # Try to fetch the source branch if it isn't known locally
  if ! git show-ref --verify --quiet "refs/heads/$SOURCE_BRANCH" 2>/dev/null && \
     ! git show-ref --verify --quiet "refs/remotes/origin/$SOURCE_BRANCH" 2>/dev/null; then
    echo "  Fetching '$SOURCE_BRANCH' from origin..."
    git fetch origin "$SOURCE_BRANCH" 2>/dev/null || true
  fi

  if ! git show-ref --verify --quiet "refs/heads/$SOURCE_BRANCH" 2>/dev/null && \
     ! git show-ref --verify --quiet "refs/remotes/origin/$SOURCE_BRANCH" 2>/dev/null; then
    echo "  [SKIP] '$SOURCE_BRANCH' not found in $name — skipping."
    cd "$ROOT_DIR"
    return 0
  fi

  # Prefer local branch; fall back to remote tracking branch
  local ref="$SOURCE_BRANCH"
  git show-ref --verify --quiet "refs/heads/$SOURCE_BRANCH" 2>/dev/null || \
    ref="origin/$SOURCE_BRANCH"

  echo "  Merging '$ref' into '$current'..."

  # shellcheck disable=SC2086  — intentional word-split for multiple flags
  if git merge $MERGE_FLAGS "$ref" 2>&1; then
    echo "  [OK] Merged cleanly."
    cd "$ROOT_DIR"
    return 0
  fi

  local conflicts
  conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null || true)

  echo "  [CONFLICT] Conflicted files:"
  echo "$conflicts" | sed 's/^/    /'

  case "$STRATEGY" in
    --ours)
      echo "  Auto-resolving with --ours (keeping $current)..."
      git checkout --ours -- .
      git add -A
      git commit --no-edit
      echo "  [OK] Resolved (ours). Review before pushing."
      ;;
    --theirs)
      echo "  Auto-resolving with --theirs (keeping $SOURCE_BRANCH)..."
      git checkout --theirs -- .
      git add -A
      git commit --no-edit
      echo "  [OK] Resolved (theirs). Review before pushing."
      ;;
    *)
      echo ""
      echo "  Manual resolution required. Steps:"
      echo "    1. Resolve the files listed above"
      echo "    2. git add <resolved-files>"
      echo "    3. git merge --continue"
      echo ""
      echo "  Re-run with a strategy to auto-resolve:"
      echo "    ./merge.sh $SOURCE_BRANCH --ours   (keep $current)"
      echo "    ./merge.sh $SOURCE_BRANCH --theirs (keep $SOURCE_BRANCH)"
      echo "    ./merge.sh $SOURCE_BRANCH --abort  (cancel)"
      echo "$name" >> "$FAILED_LOG"
      ;;
  esac

  cd "$ROOT_DIR"
}

echo "======================================================"
echo "  merge.sh  |  source: $SOURCE_BRANCH${STRATEGY:+  |  strategy: $STRATEGY}"
echo "======================================================"

git submodule foreach --quiet 'echo $displaypath' | while read -r sub; do
  merge_in "$ROOT_DIR/$sub" "$sub"
done

merge_in "$ROOT_DIR" "(root)"

echo ""
echo "======================================================"
if [[ -s "$FAILED_LOG" ]]; then
  echo "  Done — manual conflict resolution needed in:"
  while IFS= read -r repo; do
    echo "    • $repo"
  done < "$FAILED_LOG"
  echo ""
  echo "  After resolving: git add <files> && git merge --continue"
  echo "  To abort all:    ./merge.sh $SOURCE_BRANCH --abort"
else
  echo "  Done."
fi
echo "======================================================"
