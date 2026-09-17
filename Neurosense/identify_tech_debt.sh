#!/bin/bash

echo "========================================="
echo "Tech Debt Identification Report"
echo "========================================="

echo ""
echo "--- 1. TODOs and FIXMEs ---"
grep -rn "TODO\|FIXME" . | grep -v "identify_tech_debt.sh"

echo ""
echo "--- 2. Ruff Linter Errors ---"
ruff check .

echo ""
echo "--- 3. Mypy Type Checking Errors ---"
python -m mypy neurosense/

echo ""
echo "--- 4. Pending Issues in Archive ---"
ls -1 issues-archive/

echo ""
echo "========================================="
echo "End of Report"
echo "========================================="
