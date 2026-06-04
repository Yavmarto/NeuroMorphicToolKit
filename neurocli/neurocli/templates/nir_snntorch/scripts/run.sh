#!/usr/bin/env bash
set -euo pipefail
uv sync
uv run jupytext --to notebook src/train.py -o src/train.ipynb
uv run jupyter lab src/train.ipynb
