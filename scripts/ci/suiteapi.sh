#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

if [[ "${1:-}" != "--skip-install" ]]; then
  # Neurosim is intentionally absent: its package lives in neurocnl/neurosim.
  python -m pip install -e './suite_api[test]' -e './neurocnl' \
    -e './Neurochip' -e './Neurosense' \
    -e './Neurobench/neurobench' -e './Neurohub'
fi

export PYTHONPATH=".:neurocnl:Neurochip:Neurosense:Neurobench/neurobench:Neurohub"
python -m ruff check suite_api workers
python -m mypy --config-file suite_api/pyproject.toml suite_api
python -m pytest -q suite_api/tests
