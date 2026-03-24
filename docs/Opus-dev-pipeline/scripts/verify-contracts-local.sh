#!/usr/bin/env bash
#
# verify-contracts-local.sh — Run the full contract + property verification locally.
#
# This mirrors what the CI workflow does, but runs on your machine.
# Use before pushing to catch issues early.
#
# Usage:
#   bash Research-Spec-driven-development/Opus-dev-pipeline/scripts/verify-contracts-local.sh [module]
#
# Examples:
#   bash scripts/verify-contracts-local.sh           # all modules
#   bash scripts/verify-contracts-local.sh neurocnl  # just neurocnl
#
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

run_check() {
    local module="$1"
    local check_name="$2"
    local command="$3"

    printf "  %-40s " "$check_name"
    if output=$(eval "$command" 2>&1); then
        printf "${GREEN}PASS${NC}\n"
        ((PASS++))
    else
        # Check if it's a "no tests found" situation
        if echo "$output" | grep -q "no tests ran\|No contract tests\|No property tests\|FileNotFoundError\|No such file"; then
            printf "${YELLOW}SKIP${NC} (not yet created)\n"
            ((SKIP++))
        else
            printf "${RED}FAIL${NC}\n"
            echo "$output" | tail -20
            ((FAIL++))
        fi
    fi
}

verify_module() {
    local module="$1"
    local module_dir="$2"

    echo ""
    echo "━━━ $module ━━━"

    if [ ! -d "$module_dir" ]; then
        echo "  Directory not found: $module_dir"
        return
    fi

    # Type checking
    run_check "$module" "mypy contracts/" \
        "cd '$module_dir' && mypy --strict contracts/ 2>/dev/null"

    # Contract tests
    run_check "$module" "pytest contracts/" \
        "cd '$module_dir' && python -m pytest contracts/ -v --tb=short -q 2>/dev/null"

    # Property-based tests
    run_check "$module" "pytest properties/ (PBT)" \
        "cd '$module_dir' && python -m pytest properties/ -v --hypothesis-seed=0 -x --tb=short -q 2>/dev/null"

    # Standard tests (always run)
    run_check "$module" "pytest tests/ (standard)" \
        "cd '$module_dir' && python -m pytest -x --tb=short -q 2>/dev/null"
}

echo "╔══════════════════════════════════════════════╗"
echo "║  CDD+PBT Contract Verification (Local)      ║"
echo "╚══════════════════════════════════════════════╝"

TARGET="${1:-all}"

if [ "$TARGET" = "all" ] || [ "$TARGET" = "neurocnl" ]; then
    verify_module "neurocnl" "neurocnl"
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "neuro-dream-hand" ]; then
    verify_module "Neuro-Dream-Hand" "Neuro-Dream-Hand"
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "neurosim" ]; then
    verify_module "Neurosim" "Neurosim"
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "neurosense" ]; then
    verify_module "Neurosense" "Neurosense"
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "neurochip" ]; then
    verify_module "Neurochip" "Neurochip"
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "neurobench" ]; then
    verify_module "Neurobench" "Neurobench"
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "neurohub" ]; then
    verify_module "Neurohub" "Neurohub"
fi

echo ""
echo "━━━ Summary ━━━"
printf "  ${GREEN}Passed: $PASS${NC}  ${RED}Failed: $FAIL${NC}  ${YELLOW}Skipped: $SKIP${NC}\n"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "Contract verification FAILED. Fix failures before pushing."
    exit 1
else
    echo "Contract verification passed."
    exit 0
fi
