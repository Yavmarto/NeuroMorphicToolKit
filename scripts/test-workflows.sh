#!/usr/bin/env zsh
# test-workflows.sh — Lint and test GitHub Actions workflows locally
# found in the root repo and all submodules.
#
# Usage: ./test-workflows.sh [--lint] [--run] [--all]
#   --lint : (Default) Validate syntax and semantics using 'actionlint'
#   --run  : Dry-run the workflows locally using 'act'
#   --all  : Run both linting and dry-running

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LINT=false
RUN=false

# If no arguments provided, default to --lint
if [ $# -eq 0 ]; then
  LINT=true
fi

for arg in "$@"; do
  case $arg in
    --run)
      RUN=true
      ;;
    --lint)
      LINT=true
      ;;
    --all)
      LINT=true
      RUN=true
      ;;
    --help|*)
      echo "Usage: ./test-workflows.sh [--lint] [--run] [--all]"
      echo "  --lint : Lint all workflows using 'actionlint' (default)"
      echo "  --run  : Dry-run workflows locally using 'act'"
      echo "  --all  : Run both linting and dry-running"
      exit 0
      ;;
  esac
done

echo "======================================================"
echo "  test-workflows.sh — Check CI/CD workflows"
echo "======================================================"

check_dependency() {
  local cmd="$1"
  local help_msg="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[!] Missing dependency: $cmd"
    echo "    $help_msg"
    return 1
  fi
  return 0
}

MISSING_DEPS=0

if [ "$LINT" = true ]; then
  if ! check_dependency "actionlint" "Install via: brew install actionlint"; then
    MISSING_DEPS=$((MISSING_DEPS + 1))
  fi
fi

if [ "$RUN" = true ]; then
  if ! check_dependency "act" "Install via: brew install act"; then
    MISSING_DEPS=$((MISSING_DEPS + 1))
  fi
  if ! check_dependency "docker" "Install Docker Desktop for Mac to use 'act'"; then
    MISSING_DEPS=$((MISSING_DEPS + 1))
  fi
fi

if [ $MISSING_DEPS -gt 0 ]; then
  echo ""
  echo "Please install missing dependencies and try again."
  echo "Tip: Run 'brew install actionlint act'"
  exit 1
fi

# Find all workflow files in root and subdirectories
# We use grep to filter the paths to ensure we only get files in a .github/workflows directory.
WORKFLOWS=("${(@f)$(
  find "$ROOT_DIR" -type f \( -name "*.yml" -o -name "*.yaml" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/build/*" \
    -not -path "*/docs/*" \
    2>/dev/null | grep "/.github/workflows/" | sort
)}")

echo "Found ${#WORKFLOWS[@]} workflow file(s)."

FAILED=0

if [ "$LINT" = true ] && [ ${#WORKFLOWS[@]} -gt 0 ]; then
  echo ""
  echo "──────────────────────────────────────────"
  echo "  Running actionlint (Syntax & Logic Check)"
  echo "──────────────────────────────────────────"

  if actionlint "${WORKFLOWS[@]}"; then
    echo "[OK] All workflows passed linting."
  else
    echo "[FAIL] Validation errors found in workflows."
    FAILED=$((FAILED + 1))
  fi
fi

if [ "$RUN" = true ] && [ ${#WORKFLOWS[@]} -gt 0 ]; then
  echo ""
  echo "──────────────────────────────────────────"
  echo "  Dry-running Workflows with act"
  echo "──────────────────────────────────────────"
  echo "NOTE: Executing 'act -n' (dry-run)."
  echo "      To fully execute, you must run 'act' manually in the respective directory."

  for workflow in "${WORKFLOWS[@]}"; do
    repo_dir="$(dirname $(dirname $(dirname "$workflow")))"
    rel_path="${workflow#"$ROOT_DIR/"}"

    echo ""
    echo "▶ Testing: $rel_path"
    echo "------------------------------------------"

    cd "$repo_dir"

    # -n: dry run
    # -W: specify workflow file path relative to repo_dir
    rel_workflow_path=".github/workflows/$(basename "$workflow")"
    if ! act -n -W "$rel_workflow_path"; then
      echo "[FAIL] act encountered an error for $rel_path."
      FAILED=$((FAILED + 1))
    fi

    cd "$ROOT_DIR"
  done
fi

echo ""
echo "======================================================"
if [ $FAILED -eq 0 ]; then
  echo "  Success: All checks passed!"
else
  echo "  Finished with errors. Please check the logs above."
  exit 1
fi
echo "======================================================"
