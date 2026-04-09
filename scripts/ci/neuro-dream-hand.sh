#!/usr/bin/env bash
# scripts/ci/neuro-dream-hand.sh — CI for Neuro-Dream-Hand (Python, pip)
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/scripts/ci/lib.sh"
cd "$ROOT_DIR"
run_python_module "Neuro-Dream-Hand" "Neuro-Dream-Hand" "pip" "$@"
