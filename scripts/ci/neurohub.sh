#!/usr/bin/env bash
# scripts/ci/neurohub.sh — CI for Neurohub (Python, pip)
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/scripts/ci/lib.sh"
cd "$ROOT_DIR"
run_python_module "Neurohub" "Neurohub" "pip" "$@"
