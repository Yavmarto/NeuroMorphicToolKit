#!/bin/bash
set -e

# Usage: ./verify-contracts-local.sh <directory>
TARGET_DIR=${1:-neurochip}

echo "--- Running Ruff for $TARGET_DIR ---"
cd $TARGET_DIR
poetry run ruff check .

echo "--- Running Mypy for $TARGET_DIR ---"
poetry run mypy .

echo "--- Running Pytest for Contracts and Properties ---"
# Set PYTHONPATH to include the parent directory so 'neurochip' is a package
PYTHONPATH=.. poetry run pytest tests/test_contracts.py tests/properties/test_contract_properties.py

echo "--- All contracts verified successfully ---"
