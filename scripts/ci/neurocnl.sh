#!/usr/bin/env bash
# scripts/ci/neurocnl.sh — CI for neurocnl (Python, pip)
# Runs ruff/mypy from neurocnl/neurocnl/, pytest against both core and backend.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/scripts/ci/lib.sh"
cd "$ROOT_DIR"
run_python_module "neurocnl" "neurocnl" "pip" "$@"
