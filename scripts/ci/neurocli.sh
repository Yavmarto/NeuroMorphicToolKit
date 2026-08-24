#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/ci/lib.sh"
run_python_module "NeuroCLI" "neurocli" "pip_dev" "neurocli" "$@"
