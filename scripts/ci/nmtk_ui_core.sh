#!/usr/bin/env bash
# scripts/ci/nmtk_ui_core.sh — CI for nmtk_ui_core (Flutter, shared widget library)
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/scripts/ci/lib.sh"
cd "$ROOT_DIR"
run_flutter_module "nmtk_ui_core" "nmtk_ui_core"
