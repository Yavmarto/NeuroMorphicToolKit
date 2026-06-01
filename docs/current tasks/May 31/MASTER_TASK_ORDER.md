# May 31 Tasks: Master Execution Order

Based on an audit of the documents in this folder, here is the recommended execution order for the pending work. Priority is given to active bug fixes and release-blocking capabilities, followed by safe tech-debt removal, and finally architectural refactoring.

> **Last updated:** 2026-05-31 (end of session)  
> **Remaining work:** See [`REMAINING_EXECUTION_PLAN.md`](REMAINING_EXECUTION_PLAN.md) for detailed scope, key files, and execution order for all unfinished plans.

---

## 1. Immediate Bug Fix (`nir_type_check_fix.md`)
**Why:** This resolves an active, localized runtime error that prevents `.nire` files from loading in the backend. 
**Action:** Implement the `safe_nir_read()` shim and apply the try/except blocks to unblock basic functionality.

**Status:** ⬜ NOT STARTED — unblocked and ready to pick up.

---

## 2. Release Blockers (`RELEASE_GAP_ANALYSIS.md`)
**Why:** This document outlines the P0/P1 essential missing functions required for a credible product release (trust/safety, installer reliability, metrics honesty).
**Action:** Follow the "Recommended Sequencing" at the bottom of the gap analysis:
  1. Trust & safety first (auth defaults, secrets, licensing).
  2. Front-door reliability (installer + launcher state machine).
  3. Honesty of results (validated hardware path, metric provenance).
  4. Distribution hardening (signing, registry integrity).

### Release Blocker Sub-Plan Status

| Plan | Gap items | Status | Branch / Notes |
|------|-----------|--------|----------------|
| **A — Trust & Safety** | P0 #1–3, #7–8 | ✅ **DONE** | Merged to `dev` 2026-05-31 |
| **B — Front-Door Reliability** | P0 #4, #9 | ✅ **DONE** | Merged to `dev` 2026-05-31 |
| **C1 — Neurobench Metric Provenance** | P0 #6 | ✅ **DONE** | Merged to `dev` 2026-05-31 |
| **C2 — neurocnl Honesty** | P1 #11, #12 | ⬜ **PENDING** | See REMAINING_EXECUTION_PLAN.md |
| **D1 — Signed Builds** | P1 #10 | ⬜ **PENDING** | Requires signing certs |
| **D2 — Neurohub CI Green** | P1 #13 | ⬜ **PENDING** | bcrypt/passlib fix needed |
| **D3 — Golden-path CI gate** | P1 #14 | ⬜ **PENDING** | See REMAINING_EXECUTION_PLAN.md |
| **P0 #5 — Hardware Path** | P0 #5 | 🔍 **INVESTIGATE** | Requires device access |

### What Plan A delivered (merged 2026-05-31)
- `docker-compose.yml:209` Grafana password externalized via `${GRAFANA_ADMIN_PASSWORD:?}`
- Neurohub `auth_service.py` hardcoded JWT key removed; `_validate_startup_config()` fails fast in production
- `suite_api/middleware/__init__.py` CORS default changed from `"*"` to localhost-only
- `THIRD_PARTY_LICENSES.md` generated (396-package dependency manifest)
- `.env.example` updated with security variable documentation

### What Plan B delivered (merged 2026-05-31)
- `nmtk/launcher_control/server.py`: `repair_module()`, `_repair_sync()`, `POST /api/launcher/modules/{id}/repair`
- `_install_sync()` now cleans up partial venv on pip failure (rollback)
- `ControlApiService.repairModule()` + `ModuleProvider.repairModule()` in Dart
- "Repair" button in Flutter `_ModuleCard` error state with `NmtkTone.warning`
- 4 new Python unit tests + 1 Flutter widget test

### What Plan C1 delivered (merged 2026-05-31)
- `MetricProvenance(StrEnum)` with `CPU_ESTIMATED` / `ON_DEVICE` values in `benchmark_contracts.py`
- `_provenance_from_target_id()` helper (hardware targets: spinnaker2, synsense, pynq → on_device; all others → cpu_estimated)
- `BenchmarkResult.metric_provenance` field with backward-compatible default
- SQLite `ALTER TABLE` migration in `result_store.py`
- All 8 BenchmarkResult creation sites populated (runners + benchmark_runner.py)
- Flutter `result.dart` model + "CPU Estimated" / "On-Device" tone-coded badge in `ResultsSummaryCard`
- 10 new Python tests + 2 new Flutter model tests

### Also resolved (no further work needed)
- ✅ Licensing: AGPL-3.0 LICENSE files already existed across all modules
- ✅ neurocli de-listing: already absent from `modules.json`
- ✅ neurocnl auth startup warning: already logs `warning` when `AUTH_ENABLED` unset
- ✅ neurocli de-listing: already absent from `modules.json`

## 3. High-Yield Cleanup & Fluff Cuts (`2026-05-fluff-cut-analysis.md` & `2026-05-31-deprecated-code-and-docs-audit.md`)
**Plan:** [`docs/superpowers/plans/2026-05-31-tier1-fluff-cuts.md`](../../superpowers/plans/2026-05-31-tier1-fluff-cuts.md)
**Why:** The fluff cut analysis provides a ranked list of safe, high-yield tech debt removals (Tier 1). The deprecated audit provides the exact context for the `deprecated/` folders mentioned in the fluff cuts.

**Status:** Tier 1 **done** (2026-05-31). Changes are staged across the parent repo and module submodules; commit per submodule, then bump submodule pointers in the parent.

**Tier 1 completed:**
1. Deleted all module `deprecated/` folders (49 archived issue files across 7 submodules).
2. Removed tracked run artifacts (`server.log`, `simulation_report.json`) and extended root `.gitignore` for those paths plus scratch directories. `*.db`, `*.sqlite`, and `recordings/` were already gitignored.
3. Removed vendored Neurosense stub dirs (`Neurosense/neurobench/`, `Neurosense/neurocnl/`).
4. Removed root scratch directories from git (`.tmp_manual_ui/`, `Auto agentic workflows (Jules)/`, `UI - issues/`, `pitches/`, `workflow-errors/`). Left `tools/nmtk_mcp_server/` (real tooling, not Tier 1).
5. Removed committed `Neuro-Dream-Hand/output/` experiment artifacts. `site/` was not tracked.

**Remaining (Tier 2+):** Neurohub PM chrome, neurocli / Neuro-Dream-Hand reclassification, launcher setup merge, simulator deduplication, doc-tree consolidation, and all contract-dependent cuts from the fluff analysis.

## 4. Targeted Refactoring (`frontend-state-management-review.md`)
**Why:** Recommends targeted Riverpod migrations for async flows and app state. 
**Action:** This is valuable technical polish but does not block releases or unblock broken features. Schedule these migrations as isolated follow-up tasks.

## 5. Completed Work Follow-ups (`2026-05-31-sc-neurocore-deploy-targets-handoff.md`)
**Why:** The primary task described in this document is already marked as **Implemented** and passing tests.
**Action:** Review the "Follow-ups / suggestions" section (e.g., removing `getTeensyNetworkPayload` after a Mockito regen, investigating unrelated test timers) when bandwidth permits.
