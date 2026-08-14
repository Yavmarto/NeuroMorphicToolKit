#!/usr/bin/env bash
# scripts/ci/neurobench_frontend.sh — CI for Neurobench Flutter web frontend
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/scripts/ci/lib.sh"
cd "$ROOT_DIR"
run_flutter_module "Neurobench_frontend" "Neurobench/frontend"
