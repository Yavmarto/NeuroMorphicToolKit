#!/bin/bash
set -e

# Run contract-specific tests
echo "Running contract invariant tests..."
python3 -m pytest neurohub/tests/test_contract_invariants.py

# Run standard suite tests to ensure no regressions
echo "Running suite-wide tests..."
python3 -m pytest neurohub/tests/

# Run static analysis on contract files
echo "Running static analysis (mypy, ruff)..."
python3 -m mypy neurohub/contracts/
python3 -m ruff check neurohub/contracts/

echo "All contract validations passed!"
