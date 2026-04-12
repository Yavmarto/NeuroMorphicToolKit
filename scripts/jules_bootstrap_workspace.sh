#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

MODE="default"
case "$#" in
  0)
    MODE="default"
    ;;
  1)
    case "$1" in
      --verify=smoke)
        MODE="smoke"
        ;;
      --verify=integration)
        MODE="integration"
        ;;
      *)
        echo "Usage: $0 [--verify smoke|integration]" >&2
        exit 2
        ;;
    esac
    ;;
  2)
    if [[ "$1" != "--verify" ]]; then
      echo "Usage: $0 [--verify smoke|integration]" >&2
      exit 2
    fi
  case "$2" in
    smoke)
      MODE="smoke"
      ;;
    integration)
      MODE="integration"
      ;;
    *)
      echo "Usage: $0 [--verify smoke|integration]" >&2
      exit 2
      ;;
  esac
    ;;
  *)
    echo "Usage: $0 [--verify smoke|integration]" >&2
    exit 2
    ;;
esac

if [[ "$(pwd)" != "${ROOT_DIR}" ]]; then
  echo "Run this script from the NeuroMorphicToolKit repository root:" >&2
  echo "  cd ${ROOT_DIR}" >&2
  if [[ "${MODE}" == "default" ]]; then
    echo "  bash scripts/jules_bootstrap_workspace.sh" >&2
  else
    echo "  bash scripts/jules_bootstrap_workspace.sh --verify ${MODE}" >&2
  fi
  exit 1
fi

if [[ ! -f "${ROOT_DIR}/.gitmodules" || ! -d "${ROOT_DIR}/scripts" ]]; then
  echo "This does not look like the NeuroMorphicToolKit repository root." >&2
  exit 1
fi

print_header() {
  printf '\n== %s ==\n' "$1"
}

print_repo_map() {
  print_header "Repo Map"
  while read -r line; do
    sub_path="${line##* }"
    printf -- "- %s\n" "${sub_path}"
  done < <(git config --file .gitmodules --get-regexp 'submodule\..*\.path')
  printf -- "- %s\n" "NeuroMorphicToolKit (root control plane)"
}

ensure_submodules() {
  print_header "Submodule Status"
  missing=0
  while read -r status_line; do
    [[ -z "${status_line}" ]] && continue
    first_char="${status_line:0:1}"
    if [[ "${first_char}" == "-" ]]; then
      missing=1
    fi
    printf '%s\n' "${status_line}"
  done < <(git submodule status --recursive)

  if [[ "${missing}" -eq 1 ]]; then
    print_header "Initializing Missing Submodules"
    git submodule update --init --recursive
    git submodule status --recursive
  fi
}

export_service_hints() {
  export NEUROCNL_URL="${NEUROCNL_URL:-http://localhost:8000}"
  export NEUROSIM_URL="${NEUROSIM_URL:-http://localhost:8001}"
  export NEUROCHIP_URL="${NEUROCHIP_URL:-http://localhost:8002}"
  export NEUROBENCH_URL="${NEUROBENCH_URL:-http://localhost:8003}"
  export NEUROSENSE_URL="${NEUROSENSE_URL:-http://localhost:8004}"
  export NEUROHUB_URL="${NEUROHUB_URL:-http://localhost:8005}"

  print_header "Service URL Hints"
  printf 'export NEUROCNL_URL=%s\n' "${NEUROCNL_URL}"
  printf 'export NEUROSIM_URL=%s\n' "${NEUROSIM_URL}"
  printf 'export NEUROCHIP_URL=%s\n' "${NEUROCHIP_URL}"
  printf 'export NEUROBENCH_URL=%s\n' "${NEUROBENCH_URL}"
  printf 'export NEUROSENSE_URL=%s\n' "${NEUROSENSE_URL}"
  printf 'export NEUROHUB_URL=%s\n' "${NEUROHUB_URL}"
}

print_recommended_checks() {
  print_header "Recommended Checks"
  cat <<'EOF'
Single-repo work:
  Read CODING_STYLE_GUIDE.md first.
  Read the target repo's AGENTS.md and ADR/spec files first.
  Run the target repo's local tests before opening a PR.

Cross-repo contract work:
  python3 -m pytest tests/integration/test_cross_module.py
  python3 -m pytest tests/integration/test_teensy_e2e.py

Launcher or control-plane work:
  cd nmtk/neuro_toolkit && flutter test
EOF
}

run_smoke_checks() {
  print_header "Smoke Verification"
  local required_paths=(
    "AGENTS.md"
    "docs/jules/JULES_WORKSPACE_GUIDE.md"
    "tests/integration/test_cross_module.py"
    "tests/integration/test_teensy_e2e.py"
    "neurocnl/AGENTS.md"
    "neurocnl/docs/support_matrix.md"
    "neurocnl/docs/PRE_BETA_READINESS_REVIEW.md"
    "Neurosim/AGENTS.md"
    "Neurochip/AGENTS.md"
    "Neurobench/AGENTS.md"
    "Neuro-Dream-Hand/AGENTS.md"
    "Neurosense/AGENTS.md"
    "Neurohub/AGENTS.md"
    "nmtk/AGENTS.md"
    "nmtk_ui_core/AGENTS.md"
    "neurocli/AGENTS.md"
  )

  local missing_any=0
  for path in "${required_paths[@]}"; do
    if [[ -e "${ROOT_DIR}/${path}" ]]; then
      printf 'OK  %s\n' "${path}"
    else
      printf 'MISS %s\n' "${path}" >&2
      missing_any=1
    fi
  done

  if [[ "${missing_any}" -ne 0 ]]; then
    echo "Smoke verification failed: required files are missing." >&2
    exit 1
  fi
}

run_integration_checks() {
  print_header "Integration Verification"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to run integration verification." >&2
    exit 1
  fi

  python3 -m pytest tests/integration/test_cross_module.py tests/integration/test_teensy_e2e.py
}

print_header "Jules Workspace Bootstrap"
echo "Mode: ${MODE}"
echo "Root: ${ROOT_DIR}"

ensure_submodules
print_repo_map
export_service_hints
print_recommended_checks

case "${MODE}" in
  default)
    ;;
  smoke)
    run_smoke_checks
    ;;
  integration)
    run_smoke_checks
    run_integration_checks
    ;;
esac
