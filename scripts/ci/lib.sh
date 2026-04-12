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
FAIL_NAMES=()
FAIL_OUTPUTS=()

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

# _stage STAGE_NAME "shell command string"
# Runs the command, tees output to terminal, captures output on failure.
_stage() {
  local name="$1" cmd="$2"
  local tmp rc
  tmp=$(mktemp)
  { eval "$cmd"; } 2>&1 | tee "$tmp"
  rc=${PIPESTATUS[0]}
  record "$name" "$rc"
  if [ "$rc" -ne 0 ]; then
    FAIL_NAMES+=("$name")
    FAIL_OUTPUTS+=("$(cat "$tmp")")
  fi
  rm -f "$tmp"
  return "$rc"
}

_write_failure_report() {
  local mod="$1"
  local ci_dir; ci_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local timestamp; timestamp=$(date +%Y%m%d_%H%M%S)
  local report="${ci_dir}/failure_${mod}_${timestamp}.md"
  {
    echo "# CI Failure Report: ${mod}"
    echo ""
    echo "**Date:** $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "## Failed Stages"
    echo ""
    for i in "${!FAIL_NAMES[@]}"; do
      echo "### ${FAIL_NAMES[$i]}"
      echo ""
      echo '```'
      echo "${FAIL_OUTPUTS[$i]}"
      echo '```'
      echo ""
    done
  } > "$report"
  echo -e "  ${YELLOW}Failure report saved: ${report}${RESET}"
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
    _write_failure_report "$mod"
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

# run_python_module MOD DIR METHOD [TYPECHECK_TARGET] [--skip-install]
run_python_module() {
  local mod="$1" dir="$2" method="$3"
  local typecheck_target="."
  local skip_install=false
  shift 3
  if [ "$#" -gt 0 ] && [[ "$1" != --* ]]; then
    typecheck_target="$1"
    shift
  fi
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
  _stage "ruff-check" "cd '$dir' && $run_cmd ruff check ."

  echo -e "  ${CYAN}ruff format --check${RESET}"
  _stage "ruff-format" "cd '$dir' && $run_cmd ruff format --check ."

  echo -e "  ${CYAN}mypy${RESET}"
  _stage "mypy" "cd '$dir' && $run_cmd mypy '$typecheck_target'"

  echo -e "  ${CYAN}pytest${RESET}"
  if [ "$mod" = "neurocnl" ]; then
    _stage "pytest-core" "cd neurocnl && python -m pytest neurocnl/ -v --tb=short --hypothesis-show-statistics"
    if [ -f "neurocnl/backend/requirements.txt" ]; then
      _stage "pytest-backend" "cd neurocnl/backend && PYTHONPATH=. python -m pytest tests --tb=short"
    fi
  else
    _stage "pytest" "cd '$dir' && $run_cmd pytest --tb=short --hypothesis-show-statistics"
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
  _stage "analyze" "cd '$dir' && flutter analyze"

  if [ -d "$dir/test" ]; then
    echo -e "  ${CYAN}flutter test${RESET}"
    _stage "test" "cd '$dir' && flutter test"
  fi

  print_summary "$mod"
  [ "$TOTAL_FAIL" -eq 0 ] && return 0 || return 1
}
