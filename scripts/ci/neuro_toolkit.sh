#!/usr/bin/env bash
# scripts/ci/neuro_toolkit.sh — CI for neuro_toolkit (Flutter macOS launcher)
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/scripts/ci/lib.sh"
cd "$ROOT_DIR"
run_flutter_module "neuro_toolkit" "nmtk/neuro_toolkit"
