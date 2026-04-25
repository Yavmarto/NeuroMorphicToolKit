#!/usr/bin/env bash
# verify_backend.sh — monorepo guardrail for all 7 Python adapter modules.
# Usage: ./verify_backend.sh
# Exit code: 0 = clean, non-zero = regression detected.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONPATH="${ROOT}:${ROOT}/Neurochip:${ROOT}/Neurobench/neurobench:${ROOT}/Neurosense:${ROOT}/Neurohub:${ROOT}/Neurosim:${ROOT}/neurocnl:${ROOT}/Neuro-Dream-Hand:${ROOT}/nmtk${PYTHONPATH:+:$PYTHONPATH}"

# Resolve a pytest that has access to numpy, sqlalchemy, and syrupy.
# The Homebrew Python 3.11 installation at /usr/local/bin/pytest is the
# canonical test runner for this monorepo; fall back to bare `pytest` if
# the fixed path is unavailable (e.g. CI images).
if [ -x "/usr/local/bin/pytest" ]; then
  PYTEST="/usr/local/bin/pytest"
else
  PYTEST="pytest"
fi

fail() {
  echo ""
  echo "REGRESSION DETECTED. Revert changes or fix tests."
  exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# Step 1 — Lint / format check across all 7 adapter modules
# ──────────────────────────────────────────────────────────────────────────────
echo "━━━ [1/2] Running ruff lint across all 7 backend modules ━━━"
ruff check \
  "${ROOT}/neurocnl/backend/app" \
  "${ROOT}/Neurosim/neurosim/app" \
  "${ROOT}/Neurochip/neurochip/app" \
  "${ROOT}/Neurobench/neurobench/app" \
  "${ROOT}/Neurosense/neurosense/app" \
  "${ROOT}/Neurohub/neurohub/app" \
  "${ROOT}/Neuro-Dream-Hand/neurodreamhand" \
  || fail

echo ""

# ──────────────────────────────────────────────────────────────────────────────
# Step 2 — Run the full monorepo test suite
# ──────────────────────────────────────────────────────────────────────────────
echo "━━━ [2/2] Running pytest across the monorepo test suite ━━━"
"${PYTEST}" "${ROOT}/tests/" --disable-warnings || fail

echo ""
echo "✓ Backend verification passed."
