#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v pre-commit >/dev/null 2>&1; then
  echo "pre-commit is not installed. Install it with: python -m pip install pre-commit" >&2
  exit 1
fi

# Match the server workflow's pre-commit job:
#   python -m pip install pre-commit
#   pre-commit run --all-files
pre-commit run --all-files "$@"
