#!/usr/bin/env bash
# scripts/ci/lib.sh — Shared helpers for individual CI module scripts
#
# Source this file from a module script. ROOT_DIR must be set before sourcing.

# ── Colors ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Per-module result tracking ────────────────────────────────────────
RESULT_STAGES=()
RESULT_STATUS=()
TOTAL_FAIL=0

record() {
  local stage="$1" rc="$2"
  RESULT_STAGES+=("$stage")
  if [ "$rc" -eq 0 ]; then
    RESULT_STATUS+=("pass")
  else
    RESULT_STATUS+=("FAIL")
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi
}

print_summary() {
  local mod="$1"
  echo ""
  printf "  %-20s %s\n" "STAGE" "RESULT"
  printf "  %-20s %s\n" "--------------------" "------"
  for i in "${!RESULT_STAGES[@]}"; do
    local stage="${RESULT_STAGES[$i]}" status="${RESULT_STATUS[$i]}"
    if [ "$status" = "pass" ]; then
      printf "  %-20s ${GREEN}PASS${RESET}\n" "$stage"
    else
      printf "  %-20s ${RED}FAIL${RESET}\n" "$stage"
    fi
  done
  echo ""
  if [ "$TOTAL_FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}All checks passed for $mod!${RESET}"
  else
    echo -e "  ${RED}${BOLD}${TOTAL_FAIL} check(s) failed for $mod.${RESET}"
  fi
  echo ""
}

# ── Python helpers ────────────────────────────────────────────────────
_install_python_deps() {
  local mod="$1" dir="$2" method="$3"
  echo -e "  Installing deps..."

  # neurocnl requires Neuro-Dream-Hand as an extra dependency
  if [ "$mod" = "neurocnl" ] && [ -f "${ROOT_DIR}/Neuro-Dream-Hand/pyproject.toml" ]; then
    python -m pip install -e "${ROOT_DIR}/Neuro-Dream-Hand" --quiet 2>&1 | tail -1 || true
  fi

  case "$method" in
    pip)
      [ -f "$dir/pyproject.toml" ] && python -m pip install -e "./$dir" --quiet 2>&1 | tail -1 || true
      python -m pip install pytest httpx ruff mypy --quiet 2>&1 | tail -1 || true
      if [ "$mod" = "neurocnl" ] && [ -f "neurocnl/backend/requirements.txt" ]; then
        (cd neurocnl/backend && python -m pip install -r requirements.txt --quiet 2>&1 | tail -1) || true
      fi
      ;;
    pip_dev)
      [ -f "$dir/pyproject.toml" ] && python -m pip install -e "./${dir}[dev]" --quiet 2>&1 | tail -1 || true
      python -m pip install ruff mypy --quiet 2>&1 | tail -1 || true
      ;;
    poetry)
      [ -f "$dir/pyproject.toml" ] && (cd "$dir" && poetry install --no-interaction --quiet 2>&1 | tail -1) || true
      ;;
  esac
}

# run_python_module MOD DIR METHOD [--skip-install]
run_python_module() {
  local mod="$1" dir="$2" method="$3"
  local skip_install=false
  shift 3
  for arg in "$@"; do [ "$arg" = "--skip-install" ] && skip_install=true; done

  if [ ! -d "$dir" ] || [ ! -f "$dir/pyproject.toml" ]; then
    echo -e "${YELLOW}$mod: directory or pyproject.toml not found, skipping${RESET}"
    exit 1
  fi

  echo ""
  echo -e "${BOLD}======================================================"
  echo "  $mod — Python CI"
  echo "======================================================${RESET}"
  echo ""

  [ "$skip_install" = false ] && _install_python_deps "$mod" "$dir" "$method"

  local run_cmd
  [ "$method" = "poetry" ] && run_cmd="poetry run" || run_cmd="python -m"

  echo -e "  ${CYAN}ruff check${RESET}"
  (cd "$dir" && $run_cmd ruff check .) && record "ruff-check" 0 || record "ruff-check" 1

  echo -e "  ${CYAN}ruff format --check${RESET}"
  (cd "$dir" && $run_cmd ruff format --check .) && record "ruff-format" 0 || record "ruff-format" 1

  echo -e "  ${CYAN}mypy${RESET}"
  (cd "$dir" && $run_cmd mypy .) && record "mypy" 0 || record "mypy" 1

  echo -e "  ${CYAN}pytest${RESET}"
  if [ "$mod" = "neurocnl" ]; then
    (cd neurocnl && python -m pytest neurocnl/ -v --tb=short --hypothesis-show-statistics) \
      && record "pytest-core" 0 || record "pytest-core" 1
    if [ -f "neurocnl/backend/requirements.txt" ]; then
      (cd neurocnl/backend && PYTHONPATH=. python -m pytest backend/tests --tb=short 2>/dev/null) \
        && record "pytest-backend" 0 || record "pytest-backend" 1
    fi
  else
    (cd "$dir" && $run_cmd pytest --tb=short --hypothesis-show-statistics) \
      && record "pytest" 0 || record "pytest" 1
  fi

  print_summary "$mod"
  [ "$TOTAL_FAIL" -eq 0 ] && return 0 || return 1
}

# run_flutter_module MOD DIR
run_flutter_module() {
  local mod="$1" dir="$2"

  if [ ! -d "$dir" ] || [ ! -f "$dir/pubspec.yaml" ]; then
    echo -e "${YELLOW}$mod: directory or pubspec.yaml not found, skipping${RESET}"
    exit 1
  fi

  echo ""
  echo -e "${BOLD}======================================================"
  echo "  $mod — Flutter CI"
  echo "======================================================${RESET}"
  echo ""

  echo -e "  ${CYAN}flutter pub get${RESET}"
  flutter pub get --directory "$dir" --suppress-analytics > /dev/null 2>&1 || true

  echo -e "  ${CYAN}flutter analyze${RESET}"
  flutter analyze --directory "$dir" && record "analyze" 0 || record "analyze" 1

  if [ -d "$dir/test" ]; then
    echo -e "  ${CYAN}flutter test${RESET}"
    (cd "$dir" && flutter test) && record "test" 0 || record "test" 1
  fi

  print_summary "$mod"
  [ "$TOTAL_FAIL" -eq 0 ] && return 0 || return 1
}
