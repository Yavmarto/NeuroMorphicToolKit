#!/usr/bin/env bash
# scripts/ci/neurocnl_frontend.sh — CI for neurocnl Flutter web frontend
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/scripts/ci/lib.sh"
cd "$ROOT_DIR"
run_flutter_module "neurocnl_frontend" "neurocnl/frontend"
