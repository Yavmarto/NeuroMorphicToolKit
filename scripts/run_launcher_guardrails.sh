#!/usr/bin/env bash
# scripts/run_launcher_guardrails.sh — Canonical launcher/control-plane verification wrapper

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

RUN_INTEGRATION=false
FAIL_NAMES=()
FAIL_OUTPUTS=()
FAILURE_REPORT=""

for arg in "$@"; do
  case "$arg" in
    --with-integration)
      RUN_INTEGRATION=true
      ;;
    --help|-h)
      echo "Usage: ./scripts/run_launcher_guardrails.sh [--with-integration]"
      echo ""
      echo "Runs launcher doctor, then launcher unit tests and launcher Flutter tests when doctor passes."
      echo "--with-integration also runs the root integration tests for suite-visible launcher changes."
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

print_header() {
  printf '\n== %s ==\n' "$1"
}

capture_stage() {
  local stage="$1"
  shift
  local tmp rc
  tmp=$(mktemp)
  "$@" 2>&1 | tee "$tmp"
  rc=${PIPESTATUS[0]}
  if [ "$rc" -ne 0 ]; then
    FAIL_NAMES+=("$stage")
    FAIL_OUTPUTS+=("$(cat "$tmp")")
  fi
  rm -f "$tmp"
  return "$rc"
}

write_failure_report() {
  [ "${#FAIL_NAMES[@]}" -eq 0 ] && return 0

  local ci_dir timestamp report
  ci_dir="$ROOT_DIR/scripts/ci"
  timestamp=$(date +%Y%m%d_%H%M%S)
  report="${ci_dir}/failure_launcher_guardrails_${timestamp}.md"

  {
    echo "# CI Failure Report: launcher_guardrails"
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

  FAILURE_REPORT="$report"
}

require_cmd() {
  local cmd="$1"
  local hint="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required tool: $cmd" >&2
    echo "$hint" >&2
    return 1
  fi
}

# Resolve a Python 3 interpreter: tries python3, python, then the active conda
# prefix.  Prints the resolved command name/path on success.
find_python3() {
  local cmd
  for cmd in python3 python; do
    if command -v "$cmd" >/dev/null 2>&1; then
      if "$cmd" -c "import sys; exit(0 if sys.version_info.major == 3 else 1)" 2>/dev/null; then
        printf '%s\n' "$cmd"
        return 0
      fi
    fi
  done
  # Conda fallback: CONDA_PREFIX is set when a conda env is active.
  if [ -n "${CONDA_PREFIX:-}" ] && [ -x "${CONDA_PREFIX}/bin/python" ]; then
    if "${CONDA_PREFIX}/bin/python" -c "import sys; exit(0 if sys.version_info.major == 3 else 1)" 2>/dev/null; then
      printf '%s\n' "${CONDA_PREFIX}/bin/python"
      return 0
    fi
  fi
  return 1
}

print_header "Launcher Guardrails"
echo "Root: $ROOT_DIR"

STATUS=0

print_header "Environment Readiness"
PYTHON3=""
if PYTHON3="$(find_python3)"; then
  echo "Found Python 3: $PYTHON3"
else
  echo "Missing required tool: python3 (or python 3.x)" >&2
  echo "Install Python 3 or activate a conda/virtual environment that provides it." >&2
  FAIL_NAMES+=("environment_readiness")
  FAIL_OUTPUTS+=("Missing required tool: python3 (or python 3.x)"$'\n'"Install Python 3 or activate a conda environment that provides it.")
  STATUS=1
fi
if ! require_cmd flutter "Install Flutter or add it to PATH before running launcher guardrails."; then
  FAIL_NAMES+=("environment_readiness")
  FAIL_OUTPUTS+=("Missing required tool: flutter"$'\n'"Install Flutter or add it to PATH before running launcher guardrails.")
  STATUS=1
fi

if [[ "$STATUS" -ne 0 ]]; then
  echo "Launcher guardrails failed before verification because required tools are missing." >&2
  write_failure_report
  if [[ -n "$FAILURE_REPORT" ]]; then
    echo "Failure report saved: $FAILURE_REPORT" >&2
  fi
  exit "$STATUS"
fi

print_header "Launcher Doctor"
if ! capture_stage "launcher_doctor" "$PYTHON3" scripts/launcher_control_service.py --doctor --json; then
  STATUS=1
  echo "Launcher guardrails blocked by fatal launcher doctor findings." >&2
  write_failure_report
  if [[ -n "$FAILURE_REPORT" ]]; then
    echo
    echo "Failure report saved: $FAILURE_REPORT"
  fi
  exit "$STATUS"
fi

print_header "Launcher Unit Tests"
capture_stage "launcher_unit_tests" "$PYTHON3" -m unittest tests.test_launcher_control_service || STATUS=1

print_header "Launcher Flutter Tests"
capture_stage "launcher_flutter_tests" bash -lc "
cd '$ROOT_DIR/nmtk/neuro_toolkit'
flutter test
" || STATUS=1

if [[ "$RUN_INTEGRATION" == true ]]; then
  print_header "Root Integration Tests"
  capture_stage "root_integration_tests" "$PYTHON3" -m pytest tests/integration/test_cross_module.py tests/integration/test_teensy_e2e.py || STATUS=1
fi

write_failure_report
if [[ "$STATUS" -ne 0 && -n "$FAILURE_REPORT" ]]; then
  echo
  echo "Failure report saved: $FAILURE_REPORT"
fi

exit "$STATUS"
