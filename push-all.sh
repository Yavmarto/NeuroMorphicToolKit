#!/usr/bin/env bash
# push-all.sh — Wrapper to stage, commit, and push changes in all repos.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/scripts/git/push-all.sh" "$@"
