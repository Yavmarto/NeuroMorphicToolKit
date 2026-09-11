#!/usr/bin/env bash
# manage-stashes.sh — List and batch-manage git stashes across all managed repos.
# Usage:
#   manage-stashes.sh                 # Interactive selection
#   manage-stashes.sh --list          # List all stashes with dates
#   manage-stashes.sh --drop 1,3-5    # Drop specific stashes
#   manage-stashes.sh --all           # Drop all stashes across all repos
#   manage-stashes.sh --older-than 30 # Drop stashes older than 30 days
#   manage-stashes.sh --repo neurocnl # Drop stashes in a specific repo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${SCRIPT_DIR}/manage_stashes.py" "$@"
