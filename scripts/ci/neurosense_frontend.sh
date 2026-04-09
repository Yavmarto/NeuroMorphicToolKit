#!/usr/bin/env bash
# scripts/ci/neurosense_frontend.sh — CI for Neurosense Flutter web frontend
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/scripts/ci/lib.sh"
cd "$ROOT_DIR"
run_flutter_module "Neurosense_frontend" "Neurosense/frontend"
