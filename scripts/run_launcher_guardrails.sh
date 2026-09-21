#!/usr/bin/env bash
# scripts/run_launcher_guardrails.sh — Canonical launcher/control-plane verification wrapper

set -uo pipefail

# Do not inherit workstation-wide pytest concurrency flags whose plugins may
# not exist in the environment selected below.
export PYTEST_ADDOPTS="${NMTK_GUARDRAIL_PYTEST_ADDOPTS:-}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

RUN_INTEGRATION=false
RUN_K8S=false
FAIL_NAMES=()
FAIL_OUTPUTS=()
FAILURE_REPORT=""

for arg in "$@"; do
  case "$arg" in
    --with-integration)
      RUN_INTEGRATION=true
      ;;
    --with-k8s)
      RUN_K8S=true
      ;;
    --help|-h)
      echo "Usage: ./scripts/run_launcher_guardrails.sh [--with-integration] [--with-k8s]"
      echo ""
      echo "Runs launcher doctor, then launcher unit tests and launcher Flutter tests when doctor passes."
      echo "--with-integration also runs the root integration tests for suite-visible launcher changes."
      echo "--with-k8s also runs the real-cluster Kubernetes executor tests (needs kubectl + a reachable cluster)."
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

# Resolve a Python 3 interpreter that contains the guardrails' own runtime
# dependencies. Prefer an active/repository environment before system Python;
# a bare Python executable is not sufficient when it lacks packaging or pytest.
# Prints the resolved command name/path on success.
find_python3() {
  local cmd
  local candidates=()
  if [ -n "${VIRTUAL_ENV:-}" ]; then
    candidates+=("${VIRTUAL_ENV}/bin/python")
  fi
  candidates+=(
    "$ROOT_DIR/.venv/bin/python"
    "$ROOT_DIR/.test-venv/bin/python"
    python3
    python
  )
  if [ -n "${CONDA_PREFIX:-}" ]; then
    candidates+=("${CONDA_PREFIX}/bin/python")
  fi
  for cmd in "${candidates[@]}"; do
    if [[ "$cmd" == */* ]]; then
      [ -x "$cmd" ] || continue
    elif ! command -v "$cmd" >/dev/null 2>&1; then
      continue
    fi
    if "$cmd" -c "import packaging, pytest, sys; exit(0 if sys.version_info.major == 3 else 1)" 2>/dev/null; then
      printf '%s\n' "$cmd"
      return 0
    fi
  done
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
capture_stage "launcher_unit_tests" "$PYTHON3" -m pytest tests/launcher_control/ || STATUS=1

print_header "Deployment Asset Bundle"
capture_stage "deployment_asset_bundle" "$PYTHON3" scripts/sync_flutter_deployment_assets.py --check || STATUS=1

print_header "Launcher Flutter Tests"
capture_stage "launcher_flutter_tests" bash -c "
cd '$ROOT_DIR/nmtk/neuro_toolkit'
flutter test
" || STATUS=1

if [[ "$RUN_INTEGRATION" == true ]]; then
  print_header "Root Integration Tests"
  capture_stage "root_integration_tests" "$PYTHON3" -m pytest tests/integration/test_cross_module.py tests/integration/test_teensy_e2e.py || STATUS=1

  print_header "Golden Path CI Gate"
  capture_stage "golden_path_tests" "$PYTHON3" -m pytest tests/integration/test_golden_path_1.py -m golden_path -v || STATUS=1
fi

if [[ "$RUN_K8S" == true ]]; then
  print_header "Kubernetes Cluster Integration"
  # Opt-in real-cluster verification of the Kubernetes deployment executor and
  # manifest renderer. Needs kubectl pointed at a reachable cluster (the suite
  # provisions a throwaway kind cluster when K8S_KIND_PROVISION=true).
  capture_stage "kubernetes_cluster_integration" env K8S_INTEGRATION_TEST=true "$PYTHON3" -m pytest tests/integration/test_kubernetes_cluster_e2e.py -q || STATUS=1
fi

write_failure_report
if [[ "$STATUS" -ne 0 && -n "$FAILURE_REPORT" ]]; then
  echo
  echo "Failure report saved: $FAILURE_REPORT"
fi

exit "$STATUS"
