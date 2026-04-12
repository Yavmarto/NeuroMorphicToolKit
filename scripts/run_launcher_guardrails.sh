#!/usr/bin/env bash
# scripts/run_launcher_guardrails.sh — Verify launcher/control-plane readiness

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

RUN_INTEGRATION=false

for arg in "$@"; do
  case "$arg" in
    --with-integration)
      RUN_INTEGRATION=true
      ;;
    --help|-h)
      echo "Usage: ./scripts/run_launcher_guardrails.sh [--with-integration]"
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

require_cmd() {
  local cmd="$1"
  local hint="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required tool: $cmd" >&2
    echo "$hint" >&2
    return 1
  fi
}

print_header "Launcher Guardrails"
echo "Root: $ROOT_DIR"

STATUS=0

print_header "Environment Readiness"
require_cmd python3 "Install or expose python3 on PATH before running launcher guardrails." || STATUS=1
require_cmd flutter "Install Flutter or add it to PATH before running launcher guardrails." || STATUS=1

if [[ "$STATUS" -ne 0 ]]; then
  echo "Launcher guardrails failed before verification because required tools are missing." >&2
  exit "$STATUS"
fi

print_header "Launcher Doctor"
python3 scripts/launcher_control_service.py --doctor --json || STATUS=1

print_header "Launcher Unit Tests"
python3 -m unittest tests.test_launcher_control_service || STATUS=1

print_header "Launcher Flutter Tests"
(
  cd nmtk/neuro_toolkit
  flutter test
) || STATUS=1

if [[ "$RUN_INTEGRATION" == true ]]; then
  print_header "Root Integration Tests"
  python3 -m pytest tests/integration/test_cross_module.py tests/integration/test_teensy_e2e.py || STATUS=1
fi

exit "$STATUS"
