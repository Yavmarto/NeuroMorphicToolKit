#!/usr/bin/env bash
# scripts/ci/neuro-dream-hand.sh — CI for Neuro-Dream-Hand (Python, pip)
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/scripts/ci/lib.sh"
cd "$ROOT_DIR"
export NENGO_CACHE_DISABLE=1
run_python_module "Neuro-Dream-Hand" "Neuro-Dream-Hand" "pip_dev" "$@"
