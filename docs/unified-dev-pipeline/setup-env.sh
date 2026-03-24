#!/usr/bin/env bash
#
# setup-env.sh — Create and populate the verification virtual environment.
#
# Usage (from docs/unified-dev-pipeline/):
#   bash setup-env.sh               # full setup: create venv + install everything
#   bash setup-env.sh --modules-only  # only (re-)install modules, skip venv creation
#
# Why --no-deps for modules:
#   neurocnl needs fastapi>=0.109 but neurobench pins fastapi<0.101.
#   We only need the modules importable for contract + property tests — not their
#   full server stacks — so we skip transitive deps for each module install.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv-verify"
MODULES_ONLY="${1:-}"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
ok()     { echo -e "${GREEN}✓ $1${RESET}"; }
header() { echo -e "\n${BOLD}${CYAN}── $1 ──${RESET}"; }

# ── Step 1: Create venv ───────────────────────────────────────────────────────
if [[ "$MODULES_ONLY" != "--modules-only" ]]; then
  header "Creating virtual environment (.venv-verify)"

  # Find python 3.11+
  PYTHON=""
  for candidate in python3.12 python3.11 python3; do
    if command -v "$candidate" &>/dev/null; then
      version=$("$candidate" -c "import sys; print(sys.version_info[:2])")
      if "$candidate" -c "import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)" 2>/dev/null; then
        PYTHON="$candidate"
        break
      fi
    fi
  done

  if [[ -z "$PYTHON" ]]; then
    echo "ERROR: Python 3.11+ not found. Install it via:"
    echo "  conda install python=3.11  OR  brew install python@3.11"
    exit 1
  fi

  echo "  Using: $PYTHON ($($PYTHON --version))"
  "$PYTHON" -m venv "$VENV_DIR"
  ok "venv created at $VENV_DIR"

  header "Installing test/lint dependencies"
  "$VENV_DIR/bin/pip" install --quiet --upgrade pip
  "$VENV_DIR/bin/pip" install -r "$SCRIPT_DIR/requirements-verify.txt"
  ok "Core dependencies installed"
fi

# ── Step 2: Install modules with --no-deps ────────────────────────────────────
header "Installing modules (--no-deps to avoid fastapi version conflict)"

PIP="$VENV_DIR/bin/pip"

declare -A MODULES=(
  ["neurocnl"]="$REPO_ROOT/neurocnl"
  ["Neuro-Dream-Hand"]="$REPO_ROOT/Neuro-Dream-Hand"
  ["Neurobench"]="$REPO_ROOT/Neurobench/neurobench"
  ["Neurochip"]="$REPO_ROOT/Neurochip/neurochip"
  ["Neurohub"]="$REPO_ROOT/Neurohub"
  ["Neurosense"]="$REPO_ROOT/Neurosense"
  ["Neurosim"]="$REPO_ROOT/Neurosim"
)

for name in neurocnl Neuro-Dream-Hand Neurobench Neurochip Neurohub Neurosense Neurosim; do
  path="${MODULES[$name]}"
  if [[ -f "$path/pyproject.toml" ]]; then
    echo "  Installing $name (no-deps)..."
    "$PIP" install --quiet --no-deps -e "$path"
    ok "$name"
  else
    echo "  [SKIP] $name — pyproject.toml not found at $path"
  fi
done

echo ""
echo -e "${BOLD}Done. Activate with:${RESET}"
echo "  source $VENV_DIR/bin/activate"
echo ""
echo "Then run verification:"
echo "  bash run.sh --step 5"
