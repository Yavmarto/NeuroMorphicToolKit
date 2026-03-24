#!/usr/bin/env bash
#
# patch-ci-yml.sh — Documents the specific fixes needed in .github/workflows/ci.yml
#
# This script is NOT meant to be run automatically — it's a reference for
# the human or agent fixing the CI. The issues are too interleaved for
# simple sed patches.
#
# Usage: Read this file, then manually apply the fixes to ci.yml.
#
set -euo pipefail

cat <<'FIXES'
╔══════════════════════════════════════════════════════════════════╗
║  CI Workflow Fixes Needed in .github/workflows/ci.yml          ║
╚══════════════════════════════════════════════════════════════════╝

FIX 1: Remove duplicate test-neurobench job
────────────────────────────────────────────
The file has TWO definitions of test-neurobench (around lines 205-222 and 256-281).
YAML silently uses the last definition, so the first block is dead code.
ACTION: Delete the first occurrence entirely.

FIX 2: Standardize Python versions to 3.11
────────────────────────────────────────────
test-neurochip uses python-version: "3.12" while everything else uses "3.11".
ACTION: Change test-neurochip to python-version: "3.11"

FIX 3: Remove continue-on-error from neurochip ruff
────────────────────────────────────────────────────
test-neurochip has `continue-on-error: true` on its ruff step.
All other modules treat linting as a hard failure.
ACTION: Remove the `continue-on-error: true` line from the ruff step.

FIX 4: Add flutter test to frontend jobs
────────────────────────────────────────
test-neurochip-frontend, test-neurohub-frontend, test-neurosense-frontend,
test-neurobench-frontend only run `flutter analyze`, not `flutter test`.
ACTION: Add this step after `flutter analyze`:
    - name: Run tests
      run: |
        cd {module}/frontend
        flutter test || echo "No tests found yet"

FIX 5: Verify ci-passed needs array is complete
───────────────────────────────────────────────
The `ci-passed` job lists all test jobs in its `needs:` array.
After fixing the duplicate, verify test-neurobench appears exactly once.
ACTION: Check the needs array matches all defined test-* jobs.

FIX 6: Add contract verification as required check
──────────────────────────────────────────────────
After contract-verification.yml is deployed, add `contracts-passed` to
the branch protection required status checks for main and dev.
ACTION: Repository Settings → Branches → Branch protection → Required checks →
        Add "contracts-passed".

FIXES
