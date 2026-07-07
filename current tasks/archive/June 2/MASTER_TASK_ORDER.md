# June 2 Tasks: Master Execution Order

Based on the continuation of work from May 31, here is the updated execution order for the remaining unfinished tasks, prioritizing the manual implementation of Plan C2 (which replaces the broken stash) and remaining bug fixes/release blockers.

> **Last updated:** 2026-06-02 (20:10 UTC)
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
- **D3 — Golden-path CI gate** (P1 #14): ✅ COMPLETE (2026-06-02)
  - `tests/integration/test_golden_path_1.py` — already existed; all 5 steps implemented
  - `pyproject.toml` (root) — registers `golden_path` mark, `asyncio_mode = "auto"`, `asyncio_default_fixture_loop_scope`
  - `.github/workflows/golden-path.yml` — nightly + push CI workflow; starts neurocnl + Neurobench backends; runs test with graceful skip if services unavailable
- **D1 Task 2 — Windows signing** (P1 #10): ✅ COMPLETE (2026-06-02)
  - All signing artifacts already existed (`sign-installer.ps1`, `build-standalone.ps1`, `CODE_SIGNING.md`, `tests/test_windows_installer_signing.py`, `release-desktop.yml` steps)
  - `.github/workflows/ci.yml` — added `windows_installer` path filter, `test-windows-installer-signing` job, wired into `ci-passed`
- **D1 Task 3 — Update channel manifest checksums**: ⏸ DEFERRED — `update_service.dart` differential update logic is a stub; SHA-256 verification depends on finalizing the update distribution infrastructure first
- **P0 #5 — Neurochip Validated Hardware Path**: ⏸ DEFERRED — requires physical Teensy or PYNQ-Z2 device

---

## 4. Hardware Validation Fix — Akida & SC-NeuroCore Target Picker
**Why:** Blocking the hardware validation path described in `docs/Hardware Validation Plan_ PYNQ-Z2 and BrainChip AKida.md`. Two CNL Studio deploy panel bugs prevent users from reaching physical hardware.
**Action:** Implement the plan defined in `2026-06-02-akida-manage-targets-pynq-target-picker.md`.

**Status:** ⏳ AWAITING APPROVAL
- Bug 1: Akida "Manage Targets" crashes with "could not reach launcher control service" → dialog never opens
- Bug 2: SC-NeuroCore (FPGA RTL) has no PYNQ board target picker
- All changes in `neurocnl/frontend/` (6 files); no backend changes needed
- Warp plan ID: `29360f47-74f5-4290-ab39-392b387fe8e9`

---

## 5. High-Yield Cleanup & Fluff Cuts (`2026-05-fluff-cut-analysis.md`)
**Why:** Tier 1 fluff cuts were completed on May 31. Tier 2+ remains.
**Action:** Execute remaining cuts (Neurohub PM chrome, neurocli / Neuro-Dream-Hand reclassification, simulator deduplication).

**Status:** ⬜ NOT STARTED (Tier 2)

---

## 6. Targeted Refactoring (`frontend-state-management-review.md`)
**Why:** Valuable technical polish, but non-blocking.
**Action:** Targeted Riverpod migrations for async flows and app state.

**Status:** ⬜ NOT STARTED

---

## 7. UI & Design System Migration (Zeta)
**Why:** Unify the visual identity of all five frontends and remove legacy Material widgets.
**Action:** Execute the Material Icons to ZetaIcons sweep and complete remaining tech-debt button migrations.
**Status:** 🔄 IN PROGRESS (Priority currently bumped to front of queue)
- `2026-05-26-material-icons-to-zeta-icons-migration.md` (T-ICON)
- `2026-05-24-shadcn-to-zeta-flutter-migration.md` (T-UI deferred tasks)
- `2026-05-24-tech-debt-cleanup-material-deprecated.md` (T-DEBT deferred tasks)

---

## 8. Core Architecture & Authoring Experience
**Why:** Support reproducible research by separating topology from training, and provide better authoring UX.
**Action:** Implement bundle architecture, layer editor, and MCP service.
**Status:** ⬜ NOT STARTED
- `2026-05-24-nir-bundle-architecture.md` (T-BUNDLE)
- `2026-05-24-layer-editor-view.md` (T-LAYER)
- `2026-05-09-mcp-service-design.md` (MCP Service Design)

---

## 9. Usability Bug Fixes
**Why:** Stop the UI from suggesting grammar that instantly fails the compiler and ensure deploy-readiness is surfaced in the validation panel.
**Action:** Align the CNL sentence picker with NIR-native compiler rules and fix the validation panel.
**Status:** ⬜ NOT STARTED
- `2026-05-22-neurocnl-sentence-picker-nir-alignment.md` (T1-10)
- `2026-05-27-validation-deploy-readiness.md`
