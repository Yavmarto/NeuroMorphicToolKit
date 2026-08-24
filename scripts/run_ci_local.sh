#!/usr/bin/env bash
# scripts/run_ci_local.sh — Orchestrate local CI across all modules
#
# Individual module scripts live in scripts/ci/<module>.sh
# Each can also be run standalone, e.g.: ./scripts/ci/neurocnl.sh
#
# Usage:
#   ./scripts/run_ci_local.sh                # test changed modules (git diff)
#   ./scripts/run_ci_local.sh --all          # test everything
#   ./scripts/run_ci_local.sh neurocnl       # test specific module(s)
#   ./scripts/run_ci_local.sh --skip-install  # skip dep installation
#   ./scripts/run_ci_local.sh --skip-precommit # skip pre-commit hooks

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/ci/lib.sh"
# shellcheck source=scripts/dev/changed_paths.sh
source "$ROOT_DIR/scripts/dev/changed_paths.sh"

# ── Module registry ───────────────────────────────────────────────────
PY_NAMES=(SuiteAPI NeuroCLI Neurochip Neurosense Neurohub Neuro-Dream-Hand neurocnl Neurobench)
PY_DIRS=(suite_api neurocli Neurochip Neurosense/neurosense Neurohub/neurohub Neuro-Dream-Hand neurocnl Neurobench/neurobench)

FL_NAMES=(nmtk_ui_core neuro_toolkit neurocnl_frontend Neurochip_frontend Neurohub_frontend Neurosense_frontend Neurobench_frontend)
FL_DIRS=(nmtk_ui_core nmtk/neuro_toolkit neurocnl/frontend Neurochip/frontend Neurohub/frontend Neurosense/frontend Neurobench/frontend)

ALL_MODULES=("${PY_NAMES[@]}" "${FL_NAMES[@]}")
RUN_LAUNCHER_GUARDRAILS=false
RUN_LAUNCHER_INTEGRATION=false
LOCAL_FAIL_NAMES=()
LOCAL_FAIL_OUTPUTS=()
LOCAL_FAILURE_REPORT=""

# ── Parse arguments ───────────────────────────────────────────────────
MODE="changed"
SKIP_INSTALL=false
SKIP_PRECOMMIT=false
SELECTED_MODULES=()

for arg in "$@"; do
  case "$arg" in
    --all)             MODE="all" ;;
    --changed)         MODE="changed" ;;
    --skip-install)    SKIP_INSTALL=true ;;
    --skip-precommit)  SKIP_PRECOMMIT=true ;;
    --help|-h)
      echo "Usage: ./scripts/run_ci_local.sh [OPTIONS] [MODULE...]"
      echo ""
      echo "Options:"
      echo "  --all             Test all modules"
      echo "  --changed         Test only changed modules (default with no args)"
      echo "  --skip-install    Skip dependency installation"
      echo "  --skip-precommit  Skip pre-commit hooks"
      echo ""
      echo "Python modules:  ${PY_NAMES[*]}"
      echo "Flutter modules: ${FL_NAMES[*]}"
      echo ""
      echo "Individual scripts: scripts/ci/<module>.sh"
      exit 0
      ;;
    -*)
      echo "Unknown option: $arg (try --help)"
      exit 1
      ;;
    *)
      MODE="selected"
      SELECTED_MODULES+=("$arg")
      ;;
  esac
done

# ── Change detection ──────────────────────────────────────────────────
has_element() {
  local needle="$1"; shift
  for el in "$@"; do [ "$el" = "$needle" ] && return 0; done
  return 1
}

add_unique() {
  local val="$1"
  if ! has_element "$val" "${SELECTED_MODULES[@]+"${SELECTED_MODULES[@]}"}"; then
    SELECTED_MODULES+=("$val")
  fi
}

capture_local_stage() {
  local stage="$1"
  shift
  local tmp rc
  tmp=$(mktemp)
  "$@" 2>&1 | tee "$tmp"
  rc=${PIPESTATUS[0]}
  if [ "$rc" -ne 0 ]; then
    LOCAL_FAIL_NAMES+=("$stage")
    LOCAL_FAIL_OUTPUTS+=("$(cat "$tmp")")
  fi
  rm -f "$tmp"
  return "$rc"
}

write_local_failure_report() {
  [ "${#LOCAL_FAIL_NAMES[@]}" -eq 0 ] && return 0

  local ci_dir timestamp report
  ci_dir="$ROOT_DIR/scripts/ci"
  timestamp=$(date +%Y%m%d_%H%M%S)
  report="${ci_dir}/failure_run_ci_local_${timestamp}.md"

  {
    echo "# CI Failure Report: run_ci_local"
    echo ""
    echo "**Date:** $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "## Failed Root Stages"
    echo ""
    for i in "${!LOCAL_FAIL_NAMES[@]}"; do
      echo "### ${LOCAL_FAIL_NAMES[$i]}"
      echo ""
      echo '```'
      echo "${LOCAL_FAIL_OUTPUTS[$i]}"
      echo '```'
      echo ""
    done
    if [ "$TOTAL_MODULE_FAIL" -gt 0 ]; then
      echo "## Module Failures"
      echo ""
      echo "Module-specific CI scripts save their own reports under \`scripts/ci/\`."
      echo ""
      for i in "${!MOD_NAMES[@]}"; do
        if [ "${MOD_RESULTS[$i]}" = "FAIL" ]; then
          echo "- ${MOD_NAMES[$i]}"
        fi
      done
      echo ""
    fi
  } > "$report"

  LOCAL_FAILURE_REPORT="$report"
}

detect_changed_modules() {
  local base_ref
  base_ref=$(git merge-base HEAD origin/dev 2>/dev/null || git rev-parse HEAD~1 2>/dev/null || echo "")

  if [ -z "$base_ref" ]; then
    echo -e "${YELLOW}Cannot determine base ref, running all modules${RESET}"
    MODE="all"; return
  fi

  local changed_files uncommitted staged nested_uncommitted
  changed_files=$(git diff --name-only "$base_ref" HEAD 2>/dev/null || echo "")
  uncommitted=$(git diff --name-only 2>/dev/null || echo "")
  staged=$(git diff --name-only --cached 2>/dev/null || echo "")
  nested_uncommitted=$(nmtk_local_uncommitted_paths "$ROOT_DIR")
  changed_files=$(printf '%s\n%s\n%s\n%s' \
    "$changed_files" "$uncommitted" "$staged" "$nested_uncommitted" \
    | sort -u | grep -v '^$' || true)

  if [ -z "$changed_files" ]; then
    echo -e "${YELLOW}No changes detected. Use --all to test everything.${RESET}"
    exit 0
  fi

  for i in "${!PY_NAMES[@]}"; do
    local mod="${PY_NAMES[$i]}"
    local dir_prefix
    case "$mod" in
      neurocnl) dir_prefix="neurocnl/" ;;
      SuiteAPI) dir_prefix="suite_api/" ;;
      NeuroCLI) dir_prefix="neurocli/" ;;
      *)        dir_prefix="$mod/" ;;
    esac
    echo "$changed_files" | grep -q "^${dir_prefix}" && add_unique "$mod"
  done

  if echo "$changed_files" | grep -q "^nmtk_ui_core/"; then
    add_unique "nmtk_ui_core"
    for fl in neuro_toolkit neurocnl_frontend Neurochip_frontend Neurohub_frontend Neurosense_frontend Neurobench_frontend; do
      add_unique "$fl"
    done
  fi

  echo "$changed_files" | grep -q "^nmtk/neuro_toolkit/" && add_unique "neuro_toolkit"

  if echo "$changed_files" | grep -Eq '^(nmtk/neuro_toolkit/|nmtk/launcher_control/|scripts/launcher_control_service.py|scripts/run_launcher_guardrails.sh|tests/launcher_control/|AGENTS.md|CODING_STYLE_GUIDE.md|docs/jules/JULES_WORKSPACE_GUIDE.md|CONTRIBUTING.md)'; then
    RUN_LAUNCHER_GUARDRAILS=true
  fi

  if echo "$changed_files" | grep -Eq '^(nmtk/neuro_toolkit/assets/modules.json|tests/integration/test_cross_module.py|tests/integration/test_teensy_e2e.py)'; then
    RUN_LAUNCHER_INTEGRATION=true
  fi

  for i in "${!FL_NAMES[@]}"; do
    local fl="${FL_NAMES[$i]}" fl_dir="${FL_DIRS[$i]}"
    echo "$changed_files" | grep -q "^${fl_dir}/" && add_unique "$fl"
  done

  if [ ${#SELECTED_MODULES[@]} -eq 0 ]; then
    echo -e "${YELLOW}No module changes detected. Use --all to test everything.${RESET}"
    exit 0
  fi
}

# ── Resolve module list ───────────────────────────────────────────────
if [ "$MODE" = "all" ]; then
  SELECTED_MODULES=("${ALL_MODULES[@]}")
elif [ "$MODE" = "changed" ]; then
  detect_changed_modules
  [ "$MODE" = "all" ] && SELECTED_MODULES=("${ALL_MODULES[@]}")
fi

# ── Banner ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}======================================================"
echo "  Local CI — NeuroMorphicToolKit"
echo "======================================================${RESET}"
echo -e "  Modules: ${CYAN}${SELECTED_MODULES[*]}${RESET}"
if [ "$RUN_LAUNCHER_GUARDRAILS" = true ]; then
  echo -e "  Launcher guardrails: ${CYAN}enabled${RESET}"
fi
echo ""

# ── Pre-commit (global) ───────────────────────────────────────────────
PRECOMMIT_STATUS="SKIP"
if [ "$SKIP_PRECOMMIT" = false ] && command -v pre-commit >/dev/null 2>&1; then
  echo -e "${BOLD}-- Pre-commit --------------------------------------${RESET}"
  capture_local_stage "pre-commit" "$ROOT_DIR/scripts/run_precommit_local.sh" \
    && {
      PRECOMMIT_STATUS="pass"
      echo -e "${GREEN}pre-commit passed${RESET}"
    } \
    || {
      PRECOMMIT_STATUS="FAIL"
      echo -e "${RED}pre-commit failed${RESET}"
    }
  echo ""
elif [ "$SKIP_PRECOMMIT" = false ]; then
  PRECOMMIT_STATUS="FAIL"
  LOCAL_FAIL_NAMES+=("pre-commit")
  LOCAL_FAIL_OUTPUTS+=("pre-commit not installed; local CI cannot match the server pipeline (pip install pre-commit)")
  echo -e "${RED}pre-commit not installed; local CI cannot match the server pipeline (pip install pre-commit)${RESET}"
  echo ""
fi

# ── Run each module's script ──────────────────────────────────────────
MOD_NAMES=()
MOD_RESULTS=()
TOTAL_MODULE_FAIL=0

run_launcher_guardrails_stage() {
  local args=()
  [ "$RUN_LAUNCHER_INTEGRATION" = true ] && args+=("--with-integration")

  # root_integration_tests hits SUITE_API_URL, which defaults to
  # 127.0.0.1:9000 if unset. That's wrong here: the dev backend developers
  # actually edit lives on DEV_BACKEND_HOST (see Makefile), reached over
  # `make dev-update`; localhost:9000 is whatever Backend Setup happens to
  # have deployed there, which can be stale or absent. Point at the real
  # dev backend by default, but never clobber an explicit override.
  local dev_backend_host="${DEV_BACKEND_HOST:-moosebun2@192.168.2.90}"
  local suite_api_url="${SUITE_API_URL:-http://${dev_backend_host#*@}:9000}"

  if SUITE_API_URL="$suite_api_url" capture_local_stage "launcher_guardrails" bash "$ROOT_DIR/scripts/run_launcher_guardrails.sh" "${args[@]+"${args[@]}"}"; then
    MOD_NAMES+=("launcher_guardrails"); MOD_RESULTS+=("pass")
  else
    MOD_NAMES+=("launcher_guardrails"); MOD_RESULTS+=("FAIL")
    TOTAL_MODULE_FAIL=$((TOTAL_MODULE_FAIL + 1))
  fi
}

run_module() {
  local mod="$1"
  local script_name
  script_name=$(echo "$mod" | tr '[:upper:]' '[:lower:]')
  local script="$ROOT_DIR/scripts/ci/${script_name}.sh"

  if [ ! -f "$script" ]; then
    echo -e "${YELLOW}No CI script for $mod (expected $script), skipping${RESET}"
    MOD_NAMES+=("$mod"); MOD_RESULTS+=("SKIP")
    return
  fi

  local args=()
  [ "$SKIP_INSTALL" = true ] && args+=("--skip-install")

  if bash "$script" "${args[@]+"${args[@]}"}"; then
    MOD_NAMES+=("$mod"); MOD_RESULTS+=("pass")
  else
    MOD_NAMES+=("$mod"); MOD_RESULTS+=("FAIL")
    TOTAL_MODULE_FAIL=$((TOTAL_MODULE_FAIL + 1))
  fi
}

for mod in "${SELECTED_MODULES[@]}"; do
  run_module "$mod"
done

if [ "$RUN_LAUNCHER_GUARDRAILS" = true ]; then
  run_launcher_guardrails_stage
fi

# ── Consolidated summary ──────────────────────────────────────────────
echo ""
echo -e "${BOLD}======================================================"
echo "  Overall Results"
echo "======================================================${RESET}"
echo ""
printf "  %-30s %s\n" "MODULE" "RESULT"
printf "  %-30s %s\n" "------------------------------" "------"
if [ "$PRECOMMIT_STATUS" = "pass" ]; then
  printf "  %-30s ${GREEN}PASS${RESET}\n" "pre-commit"
elif [ "$PRECOMMIT_STATUS" = "FAIL" ]; then
  printf "  %-30s ${RED}FAIL${RESET}\n" "pre-commit"
else
  printf "  %-30s ${YELLOW}SKIP${RESET}\n" "pre-commit"
fi
for i in "${!MOD_NAMES[@]}"; do
  local_mod="${MOD_NAMES[$i]}"
  local_status="${MOD_RESULTS[$i]}"
  if [ "$local_status" = "pass" ]; then
    printf "  %-30s ${GREEN}PASS${RESET}\n" "$local_mod"
  elif [ "$local_status" = "SKIP" ]; then
    printf "  %-30s ${YELLOW}SKIP${RESET}\n" "$local_mod"
  else
    printf "  %-30s ${RED}FAIL${RESET}\n" "$local_mod"
  fi
done
echo ""
OVERALL_FAIL=$TOTAL_MODULE_FAIL
[ "$PRECOMMIT_STATUS" = "FAIL" ] && OVERALL_FAIL=$((OVERALL_FAIL + 1))
write_local_failure_report
if [ "$OVERALL_FAIL" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}All modules passed!${RESET}"
else
  echo -e "  ${RED}${BOLD}${OVERALL_FAIL} stage(s) failed.${RESET}"
  if [ -n "$LOCAL_FAILURE_REPORT" ]; then
    echo -e "  ${YELLOW}Failure report saved: ${LOCAL_FAILURE_REPORT}${RESET}"
  fi
fi
echo ""

[ "$OVERALL_FAIL" -eq 0 ] && exit 0 || exit 1
