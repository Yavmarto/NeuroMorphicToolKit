# Plan C2: neurocnl Validation & Export Honesty (Manual Implementation)

**Context:** The original `stash@{6}` attempt for Plan C2 was abandoned because it was based on an outdated branch state (`eeba658`) and contained thousands of lines of unrelated, conflicting code (causing 78+ test failures). We will instead implement the precise, scoped requirements of Plan C2 manually on the current clean `dev` branch.

## Requirements

### 1. Backend: Ensure `backend_support` is populated
- **File:** `neurocnl/backend/app/routers/validate.py` (and related validation schemas/logic)
- **Goal:** Ensure that a `POST /api/validate` call always correctly populates the `backend_support` field (e.g. returning a `BackendSupport` object with a verdict of `"faithful"`, `"approximate"`, or `"unsupported"`).
- **Why:** The frontend relies on this field to determine deploy readiness.

### 2. Frontend: Render "Deploy Blocked" in the Validation Panel
- **File:** `neurocnl/frontend/lib/widgets/validation_panel.dart`
- **Goal:** When `backend_support.verdict == "unsupported"`, render a prominent "Deploy Blocked" indicator (using the appropriate danger tone/style) alongside the standard Layer 1/2 results.
- **Why:** To ensure a user never sees a "green" validation panel but a "red" deploy panel without an explanation.

### 3. Backend: Add `/api/export/preflight` endpoint
- **File:** `neurocnl/backend/app/routers/export.py`
- **Goal:** Add a new POST endpoint (e.g., `/api/export/preflight`) that accepts an export format and a spec, and returns the capability verdict (`backend_support`) WITHOUT generating artifacts.
- **Why:** Allows the export dialog to warn the user about topological constraints (like sinabs requiring sequential-only graphs) *before* they click export.

## Verification
- Run Backend tests: `cd neurocnl && PYTHONPATH=. pytest neurocnl/tests/ backend/tests/ -p no:nengo -v --tb=short`
- Run Frontend tests: `cd neurocnl/frontend && flutter test`
