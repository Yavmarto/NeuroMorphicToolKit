#!/usr/bin/env bash
# scripts/ci/neurobench.sh — CI for Neurobench (Python, poetry)
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/scripts/ci/lib.sh"
cd "$ROOT_DIR"
run_python_module "Neurobench" "Neurobench/neurobench" "poetry" "$@"
