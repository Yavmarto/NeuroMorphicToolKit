# June 2 Tasks: Master Execution Order

Based on the continuation of work from May 31, here is the updated execution order for the remaining unfinished tasks, prioritizing the manual implementation of Plan C2 (which replaces the broken stash) and remaining bug fixes/release blockers.

> **Last updated:** 2026-06-02
> **Note:** The `May 31` stash for Plan C2 was abandoned due to massive structural conflicts. We are proceeding with a clean manual implementation.

---

## 1. Plan C2 (Manual Implementation) — neurocnl Honesty
**Why:** Replaces the broken `stash@{6}` attempt. This is a P1 release blocker to ensure the UI surfaces contradictory signals to users when a hardware deployment is blocked by topology rules.
**Action:** Implement the scoped changes defined in [`Plan_C2_Manual_Implementation.md`](Plan_C2_Manual_Implementation.md).

**Status:** ✅ COMPLETE (2026-06-02)
- `backend/app/routers/validate.py` — backend_support always non-null (verdict="unsupported" fallback)
- `backend/app/routers/export.py` — POST /api/export/preflight endpoint (5 new tests, handles all failure paths)
- `frontend/lib/widgets/validation_panel.dart` — _BackendSupportBanner widget (5 new tests)
- 28/28 backend tests ✅, 11/11 frontend validation tests ✅

---

## 2. Immediate Bug Fix (`nir_type_check_fix.md`)
**Why:** This resolves an active, localized runtime error that prevents `.nire` files from loading in the backend. 
**Action:** Implement the `safe_nir_read()` shim and apply the try/except blocks to unblock basic functionality.

**Status:** ✅ COMPLETE — already implemented prior to 2026-06-02
- `neurocnl/_nir_compat.py` — safe_nir_read() + NIR_READ_HAS_TYPE_CHECK flag + make_nir_graph() fallback (commit e169ae8)
- `neurosim/app/routers/generation.py` — replaced nir.read() with safe_nir_read() in both call sites (commit 1c8b678)

---

## 3. Release Blockers Remaining (`REMAINING_EXECUTION_PLAN.md`)
**Why:** Continuation of the missing functions required for a credible product release from the Gap Analysis.

### Outstanding Plans:
- **D3 — Golden-path CI gate** (P1 #14): 🔄 IN PROGRESS
- **D1 Task 2 — Windows signing** (P1 #10): 🔄 IN PROGRESS
- **D1 Task 3 — Update channel manifest checksums**: ⏸ DEFERRED — `update_service.dart` differential update logic is a stub; SHA-256 verification depends on finalizing the update distribution infrastructure first
- **P0 #5 — Neurochip Validated Hardware Path**: ⏸ DEFERRED — requires physical Teensy or PYNQ-Z2 device

---

## 4. High-Yield Cleanup & Fluff Cuts (`2026-05-fluff-cut-analysis.md`)
**Why:** Tier 1 fluff cuts were completed on May 31. Tier 2+ remains.
**Action:** Execute remaining cuts (Neurohub PM chrome, neurocli / Neuro-Dream-Hand reclassification, simulator deduplication).

**Status:** ⬜ NOT STARTED (Tier 2)

---

## 5. Targeted Refactoring (`frontend-state-management-review.md`)
**Why:** Valuable technical polish, but non-blocking.
**Action:** Targeted Riverpod migrations for async flows and app state.

**Status:** ⬜ NOT STARTED
