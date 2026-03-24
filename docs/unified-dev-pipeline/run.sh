#!/usr/bin/env bash
#
# run.sh — Unified CDD+PBT pipeline runner.
# Run from the unified-dev-pipeline/ directory:
#
#   cd docs/unified-dev-pipeline
#   bash run.sh [--step N] [--dry-run] [--module <name>]
#
# Steps:
#   1  audit      — Print workflow gap matrix for all modules
#   2  preview    — Generate issue previews locally as markdown (no GitHub calls)
#   3  publish    — Publish issues to GitHub (dry-run unless --execute or step is explicit)
#   4  install-ci — Copy CI workflows + PR/issue templates to .github/
#   5  verify     — Run contract + property-based tests locally
#   6  baselines  — Generate golden simulation baselines (run after neurocnl is working)
#
# Without --step, runs steps 1-3 in sequence (safe default: step 3 is dry-run).
# Pass --execute to actually publish issues in step 3.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PIPELINE_DIR="$SCRIPT_DIR"

# ── Argument parsing ─────────────────────────────────────────────────────────
STEP=""
EXECUTE=""
MODULE_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --step)    STEP="$2";    shift 2 ;;
    --execute) EXECUTE="--execute"; shift ;;
    --module)  MODULE_ARG="--module $2"; shift 2 ;;
    -h|--help)
      sed -n '/^#/p' "$0" | sed 's/^# \{0,1\}//' | head -20
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'; GREEN='\033[0;32m'

header() { echo; echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; echo -e "${BOLD}${CYAN}  Step $1: $2${RESET}"; echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; }
ok()     { echo -e "${GREEN}✓ $1${RESET}"; }

# ── Step functions ────────────────────────────────────────────────────────────

step_audit() {
  header 1 "Audit — module workflow gap matrix"
  python "$PIPELINE_DIR/scripts/audit_workflows.py" --root "$PIPELINE_DIR"
  ok "Audit complete."
}

step_preview() {
  header 2 "Preview — generate issue markdown files locally"
  python "$PIPELINE_DIR/scripts/generate_issue_previews.py" --root "$PIPELINE_DIR" $MODULE_ARG
  ok "Previews written to each module's generated-issues/ directory."
}

step_publish() {
  header 3 "Publish — send issues to GitHub"
  if [[ -z "$EXECUTE" ]]; then
    echo -e "  ${CYAN}DRY-RUN mode${RESET} — pass --execute to actually publish."
  fi
  python "$PIPELINE_DIR/scripts/publish_github_issues.py" --root "$PIPELINE_DIR" $EXECUTE $MODULE_ARG
  ok "Publish step complete."
}

step_install_ci() {
  header 4 "Install CI — copy workflows + templates to .github/"
  local workflows_src="$PIPELINE_DIR/.github/workflows"
  local workflows_dst="$REPO_ROOT/.github/workflows"
  local templates_src="$PIPELINE_DIR/.github/ISSUE_TEMPLATE"
  local templates_dst="$REPO_ROOT/.github/ISSUE_TEMPLATE"
  local pr_template="$PIPELINE_DIR/.github/PULL_REQUEST_TEMPLATE.md"

  if [[ ! -d "$workflows_src" ]]; then
    echo "  [SKIP] No .github/workflows/ found in pipeline dir — skipping."
    return 0
  fi

  mkdir -p "$workflows_dst" "$templates_dst"

  echo "  Copying workflows..."
  cp "$workflows_src"/*.yml "$workflows_dst/"

  if [[ -f "$pr_template" ]]; then
    echo "  Copying PR template..."
    cp "$pr_template" "$REPO_ROOT/.github/PULL_REQUEST_TEMPLATE.md"
  fi

  if [[ -d "$templates_src" ]]; then
    echo "  Copying issue templates..."
    cp "$templates_src"/*.yml "$templates_dst/"
  fi

  ok "CI files installed. Commit with: git add .github/ && git commit -m 'ci: add unified CDD+PBT workflows'"
}

step_verify() {
  header 5 "Verify — run contracts + property tests locally"
  bash "$PIPELINE_DIR/scripts/verify-contracts-local.sh" $MODULE_ARG
  ok "Verification complete."
}

step_baselines() {
  header 6 "Baselines — generate golden simulation baselines"
  echo "  Note: only run this after neurocnl contracts are installed and passing."
  bash "$PIPELINE_DIR/scripts/generate-golden-baselines.sh"
  ok "Baselines generated."
}

# ── Dispatch ──────────────────────────────────────────────────────────────────

echo -e "${BOLD}Unified CDD+PBT Pipeline — $(date '+%Y-%m-%d %H:%M')${RESET}"
echo -e "  Pipeline dir : $PIPELINE_DIR"
echo -e "  Repo root    : $REPO_ROOT"
[[ -n "$MODULE_ARG" ]] && echo -e "  Module filter: $MODULE_ARG"
[[ -n "$EXECUTE"    ]] && echo -e "  Mode         : EXECUTE (will publish to GitHub)"
[[ -z "$EXECUTE"    && ( -z "$STEP" || "$STEP" == "3" ) ]] && echo -e "  Mode         : dry-run for publish (pass --execute to push issues)"

case "$STEP" in
  "")
    # Default: steps 1-3 (audit → preview → dry-run or execute publish)
    step_audit
    step_preview
    step_publish
    ;;
  1) step_audit    ;;
  2) step_preview  ;;
  3) step_publish  ;;
  4) step_install_ci ;;
  5) step_verify   ;;
  6) step_baselines ;;
  *)
    echo "Unknown step: $STEP. Valid steps: 1-6"
    exit 1
    ;;
esac

echo
echo -e "${BOLD}Done.${RESET}"
