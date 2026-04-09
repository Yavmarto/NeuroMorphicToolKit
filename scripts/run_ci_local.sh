#!/usr/bin/env bash
# scripts/run_ci_local.sh — Orchestrate local CI across all modules
#
# Individual module scripts live in scripts/ci/<module>.sh
# Each can also be run standalone, e.g.: ./scripts/ci/neurosim.sh
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

# ── Module registry ───────────────────────────────────────────────────
PY_NAMES=(Neurosim Neurochip Neurosense Neurohub Neuro-Dream-Hand neurocnl Neurobench)
PY_DIRS=(Neurosim Neurochip Neurosense/neurosense Neurohub/neurohub Neuro-Dream-Hand neurocnl Neurobench/neurobench)

FL_NAMES=(nmtk_ui_core neuro_toolkit neurocnl_frontend Neurochip_frontend Neurohub_frontend Neurosense_frontend Neurobench_frontend)
FL_DIRS=(nmtk_ui_core nmtk/neuro_toolkit neurocnl/frontend Neurochip/frontend Neurohub/frontend Neurosense/frontend Neurobench/frontend)

ALL_MODULES=("${PY_NAMES[@]}" "${FL_NAMES[@]}")

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

detect_changed_modules() {
  local base_ref
  base_ref=$(git merge-base HEAD origin/dev 2>/dev/null || git rev-parse HEAD~1 2>/dev/null || echo "")

  if [ -z "$base_ref" ]; then
    echo -e "${YELLOW}Cannot determine base ref, running all modules${RESET}"
    MODE="all"; return
  fi

  local changed_files uncommitted staged
  changed_files=$(git diff --name-only "$base_ref" HEAD 2>/dev/null || echo "")
  uncommitted=$(git diff --name-only 2>/dev/null || echo "")
  staged=$(git diff --name-only --cached 2>/dev/null || echo "")
  changed_files=$(printf '%s\n%s\n%s' "$changed_files" "$uncommitted" "$staged" | sort -u | grep -v '^$' || true)

  if [ -z "$changed_files" ]; then
    echo -e "${YELLOW}No changes detected. Use --all to test everything.${RESET}"
    exit 0
  fi

  for i in "${!PY_NAMES[@]}"; do
    local mod="${PY_NAMES[$i]}"
    local dir_prefix
    case "$mod" in
      neurocnl) dir_prefix="neurocnl/" ;;
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
echo ""

# ── Pre-commit (global) ───────────────────────────────────────────────
if [ "$SKIP_PRECOMMIT" = false ] && command -v pre-commit >/dev/null 2>&1; then
  echo -e "${BOLD}-- Pre-commit --------------------------------------${RESET}"
  pre-commit run --all-files \
    && echo -e "${GREEN}pre-commit passed${RESET}" \
    || echo -e "${RED}pre-commit failed${RESET}"
  echo ""
elif [ "$SKIP_PRECOMMIT" = false ]; then
  echo -e "${YELLOW}pre-commit not installed, skipping (pip install pre-commit)${RESET}"
  echo ""
fi

# ── Run each module's script ──────────────────────────────────────────
MOD_NAMES=()
MOD_RESULTS=()
TOTAL_MODULE_FAIL=0

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

# ── Consolidated summary ──────────────────────────────────────────────
echo ""
echo -e "${BOLD}======================================================"
echo "  Overall Results"
echo "======================================================${RESET}"
echo ""
printf "  %-30s %s\n" "MODULE" "RESULT"
printf "  %-30s %s\n" "------------------------------" "------"
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
if [ "$TOTAL_MODULE_FAIL" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}All modules passed!${RESET}"
else
  echo -e "  ${RED}${BOLD}${TOTAL_MODULE_FAIL} module(s) failed.${RESET}"
fi
echo ""

[ "$TOTAL_MODULE_FAIL" -eq 0 ] && exit 0 || exit 1
