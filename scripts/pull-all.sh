#!/usr/bin/env bash
# pull-all.sh — Wrapper to pull latest changes in all repos.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/git/pull-all.sh" "$@"
