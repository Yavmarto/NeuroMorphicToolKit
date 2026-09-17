#!/bin/bash
set -e

# NeuroSim Contract Verification Script
# This script verifies that the NeuroSim design contracts are consistent,
# properly type-checked, and pass property-based tests.

echo "Running MyPy on design contracts..."
python -m mypy neurosim/contracts/design_contracts.py

echo "Running property-based tests for contracts..."
PYTHONPATH=. python -m pytest neurosim/tests/properties/test_design_properties.py

echo "Contract verification passed!"
