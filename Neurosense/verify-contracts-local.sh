#!/bin/bash
set -e

# Usage: ./verify-contracts-local.sh <package_name>
PACKAGE_NAME=${1:-neurosense}

echo "Verifying contracts for $PACKAGE_NAME..."

# Run static type checking on contracts
echo "Running mypy..."
mypy $PACKAGE_NAME/contracts/

# Run contract tests
echo "Running pytest..."
PYTHONPATH=. pytest $PACKAGE_NAME/tests/test_contracts.py

echo "Contract verification passed!"
