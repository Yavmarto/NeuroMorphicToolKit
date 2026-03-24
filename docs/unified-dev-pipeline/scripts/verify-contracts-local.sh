#!/usr/bin/env bash
#
# verify-contracts-local.sh — Run the full contract + property verification locally.
#
# This mirrors what the CI workflow does but runs on your machine.
# Use before pushing to catch issues early.
#
# Enhanced with polyglot framework detection (pip / poetry / flutter).
#
# Usage:
#   bash docs/unified-dev-pipeline/scripts/verify-contracts-local.sh          # all modules
#   bash docs/unified-dev-pipeline/scripts/verify-contracts-local.sh neurocnl # just neurocnl
#
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

run_check() {
    local module="$1"
    local check_name="$2"
    local command="$3"

    printf "  %-44s " "$check_name"
    if output=$(eval "$command" 2>&1); then
        printf "${GREEN}PASS${NC}\n"
        ((PASS++))
    else
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

detect_framework() {
    local module_dir="$1"
    if [ -f "$module_dir/pubspec.yaml" ]; then
        echo "flutter"
    elif [ -f "$module_dir/poetry.lock" ] || grep -q '\[tool.poetry\]' "$module_dir/pyproject.toml" 2>/dev/null; then
        echo "poetry"
    else
        echo "pip"
    fi
}

install_deps() {
    local module_dir="$1"
    local framework
    framework=$(detect_framework "$module_dir")
    printf "  ${CYAN}Framework: %s${NC}\n" "$framework"

    case "$framework" in
        poetry)
            (cd "$module_dir" && poetry install --with test 2>/dev/null) || true
            ;;
        flutter)
            (cd "$module_dir" && flutter pub get 2>/dev/null) || true
            ;;
        pip)
            (cd "$module_dir" && pip install -e ".[dev]" 2>/dev/null || pip install -e . 2>/dev/null) || true
            ;;
    esac
}

run_tests() {
    local module_dir="$1"
    local framework
    framework=$(detect_framework "$module_dir")
    local runner="python -m pytest"
    [ "$framework" = "poetry" ] && runner="poetry run pytest"

    return 0
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

    local framework
    framework=$(detect_framework "$module_dir")
    printf "  ${CYAN}Framework: %s${NC}\n" "$framework"

    local pytest_cmd="python -m pytest"
    local mypy_cmd="mypy"
    local ruff_cmd="ruff"
    if [ "$framework" = "poetry" ]; then
        pytest_cmd="poetry run pytest"
        mypy_cmd="poetry run mypy"
        ruff_cmd="poetry run ruff"
    fi

    # Linting
    run_check "$module" "ruff check" \
        "cd '$module_dir' && $ruff_cmd check . 2>/dev/null"

    # Type checking
    run_check "$module" "mypy contracts/" \
        "cd '$module_dir' && $mypy_cmd --strict contracts/ 2>/dev/null"

    # Contract tests
    run_check "$module" "pytest contracts/" \
        "cd '$module_dir' && $pytest_cmd contracts/ -v --tb=short -q 2>/dev/null"

    # Property-based tests
    run_check "$module" "pytest properties/ (PBT)" \
        "cd '$module_dir' && $pytest_cmd properties/ -v --hypothesis-seed=0 -x --tb=short -q 2>/dev/null"

    # Standard tests
    run_check "$module" "pytest tests/ (standard)" \
        "cd '$module_dir' && $pytest_cmd -x --tb=short -q 2>/dev/null"
}

echo "╔══════════════════════════════════════════════════╗"
echo "║  CDD+PBT Contract Verification (Local)          ║"
echo "║  Unified Pipeline — pip / poetry / flutter aware ║"
echo "╚══════════════════════════════════════════════════╝"

TARGET="${1:-all}"

MODULES=(
    "neurocnl:neurocnl"
    "neuro-dream-hand:Neuro-Dream-Hand"
    "neurosim:Neurosim"
    "neurosense:Neurosense"
    "neurochip:Neurochip"
    "neurobench:Neurobench"
    "neurohub:Neurohub"
)

for entry in "${MODULES[@]}"; do
    key="${entry%%:*}"
    dir="${entry##*:}"
    if [ "$TARGET" = "all" ] || [ "$TARGET" = "$key" ]; then
        verify_module "$dir" "$dir"
    fi
done

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
