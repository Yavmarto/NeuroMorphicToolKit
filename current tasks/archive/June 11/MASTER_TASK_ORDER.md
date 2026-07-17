# June 11 Tasks: Master Execution Order

## Verified Implementation Status (2026-07-04)

Re-checked against the actual `neurocnl` submodule (git history + current file contents) roughly three weeks after this doc's "verified 2026-06-10/11" snapshot. All three items have moved since then; the doc's per-item statuses below are now stale in places.

**1. CML Studio / Hub / Bench Integration — Status: now PARTIAL, more done than doc claims.**
- ✅ Task 1 (Hub workspace import UI in `setup_step.dart`) is now wired, contradicting the doc's "❌ not wired". Evidence: `neurocnl/frontend/lib/screens/studio/steps/setup_step.dart` has `_openWorkspaceFromHub()`, a `_HubWorkspacePickerDialog` (ConsumerWidget watching `hubStudioWorkspaceProvider`), and a "Load from Hub" menu entry. Added in submodule commit `c0b40479 hub switch` (the doc itself lists this as a "recent commit" but hadn't yet reflected its contents), refined in `cf0dd409 fix: viz-demo nav entry point, jobs.db data dir, and ListTile/Material crash` (2026-07-01).
- ✅ Task 3 (Share → publish-back-to-Hub) is now wired, contradicting the doc's "❌ not connected to export flow". Evidence: `hub_asset_client.dart`'s `publishWorkspace()` is called from `neurocnl/frontend/lib/screens/studio/deploy/deploy_workspace_panel.dart:289` (`_publishWorkspace()`) and `neurocnl/frontend/lib/screens/studio/steps/results_step.dart:455`.
- ❌ Task 2 (Bench as workspace lifecycle step) — still no evidence found (no `BenchStep`/`bench_step`/lifecycle-step file in `frontend/lib/screens/studio`). Matches doc's "not started".
- ❓ Task 4 (compatibility router redirects) — `neurocnl/frontend/lib/routing/app_router.dart` does have `redirect:` handlers, but they're generic legacy-deep-link redirects (`/?panel=deploy`, `/?panel=hardware`, `/?panel=analysis`), not obviously the Hub-specific compatibility redirects the plan describes. Inconclusive either way.
- ❓ Task 5 (NeuroSim isolation) — `frontend/lib/routing/canvas/neurosim_workspace_controller.dart` and `neurosim_restoration_snapshot.dart` exist and suggest isolation-style architecture, but it's unclear whether this satisfies the specific Task 5 requirement or predates it. Still unclear, as the doc says.

**2. State Machine Migration (Phases 2–3) — Status: now PARTIAL, doc's "Phase 1 only" is stale.**
- Phase 1 (data models) confirmed still in place: `SimulatorRunState`/`SimulatorState`, `PipelineState`, `NirImportState` (Freezed) at `neurocnl/frontend/lib/src/features/studio/domain/`.
- Phase 2/3 evidence of real progress contradicting "❌ not started": `neurocnl/frontend/lib/providers/nir_import_provider.dart:83` has an exhaustive `switch (state)` over all four `NirImportState` variants (`Idle`/`Loading`/`Loaded`/`Error`) inside the notifier. On the UI side, `neurocnl/frontend/lib/widgets/nir_importer_tab.dart` has two exhaustive `switch (state)` expressions over `NirImportState` (lines ~55 and ~193) driving both the header and the body widget — this is precisely the Phase 3 pattern the plan calls for ("Refactor ConsumerWidgets to use Dart 3 `switch` expressions").
- But it's not migrated everywhere: `neurocnl/frontend/lib/widgets/pipeline_bar.dart` mixes an exhaustive `switch (status)` over the plain `TrainingProviderStatus` enum (not a Freezed union) with old-style `if (pipeline.generateStatus == StepStatus.error) ... else if (...)` chains for deploy status — the defensive-check pattern Phase 3 is supposed to eliminate is still present there.
- Backend: no `match`/`case` over `JobState`/`SimulationState` discriminated unions was found; existing `match response.status: case SimulationStatus.FAILED / CANCELLED` in `neurosim/app/services/{sweep_runner,preview_runner}.py` matches over a plain enum, not the Pydantic discriminated union the plan calls for.
- Net: call it Phase 2/3 "started, uneven" rather than "not started" — NIR import is fully migrated end-to-end; pipeline/training and the backend are not.

**3. Material Widget Sweep — Status: consistent with doc's own "in progress", counts have shifted (mostly downward) since 2026-06-11.**
- Rough `grep` counts of `MaterialButton|ElevatedButton|TextButton|OutlinedButton|FilledButton` today: `neurocnl/frontend/lib` 41, `Neurohub/frontend/lib` 9, `Neurobench/frontend/lib` 5, `nmtk/neuro_toolkit/lib` 1. These don't line up 1:1 with the doc's per-repo counts (11/9/8/11) — `nmtk/neuro_toolkit` in particular looks much further along (1 vs. 11), while `neurocnl/frontend` looks higher (41 vs. 11), likely because the doc's count used a narrower pattern (e.g. only flagged non-conforming usages) than this raw grep. Either way, the sweep is real but incomplete everywhere except Neurosense (0 hits, consistent with doc's "100% complete").
- `ZetaIcons.*` usage (separate T-ICON item, #4 in this doc): 130 usages found repo-wide today vs. doc's "0 usages... NOT STARTED" — so the icon migration has since begun in some form, even though this doc still marks it unstarted. `Icons.*` in `neurocnl/frontend/lib` alone is now 379 (doc: 316), so both old and new patterns are growing, consistent with a sweep that started but a codebase that also kept growing.

> **Last updated:** 2026-06-11
> **Previous:** `archive/June 2/MASTER_TASK_ORDER.md`
> **Note:** Statuses verified against actual codebase on 2026-06-10/11. Several June 2 statuses were stale.

---

## 1. CML Studio / Hub / Bench Integration
**Why:** Unifies workspace lifecycle — Hub as source and sink for Studio workspaces and Bench runs. Active work in progress (recent commits: `ae637de` hub switch, `741ab2a` tool_view restore).
**Action:** Complete the 5 tasks in [`../archive/June 9/2026-06-09-cml-studio-workspace-hub-plan.md`](../archive/June%209/2026-06-09-cml-studio-workspace-hub-plan.md).
**Status:** 🔄 IN PROGRESS

**Verified implementation:**
- ✅ `HubAssetClient` service — `listStudioWorkspaces()`, `downloadAssetBytes()`, `publishWorkspace()` implemented
- ✅ Riverpod providers — `hubAssetClientProvider`, `hubStudioWorkspaceProvider` in `hub_asset_provider.dart`
- ❌ Task 1: Hub workspace import UI in `setup_step.dart` — not wired
- ❌ Task 2: Bench as workspace lifecycle step — not started
- ❌ Task 3: Share → publish-back-to-Hub UI — `publishWorkspace()` exists but not connected to export flow
- ❌ Task 4: Compatibility (router redirects for legacy entry points) — not started
- ❓ Task 5: NeuroSim isolation — status unclear

---

## 2. State Machine Migration (Phases 2–3)
**Why:** Phase 1 (data models) is complete. Phases 2–3 (state controllers, UI integration) are not started. This underpins the CML Studio Hub work and general reliability.
**Action:** Complete the migration defined in [`../archive/June 8/state_machine_migration_plan.md`](../archive/June%208/state_machine_migration_plan.md).
**Status:** 🔄 IN PROGRESS (Phase 1 only)

**Verified implementation:**
- ✅ Phase 1 — Data models: `SimulatorRunState`, `PipelineState`, `NirImportState` (Freezed); `JobState` discriminated union (Pydantic)
- ❌ Phase 2 — State controllers: Notifiers exist but no exhaustive `switch`/`match-case` transitions
- ❌ Phase 3 — UI integration: No Dart switch expressions over Freezed states; defensive checks not yet removed

---

## 3. Material Widget Sweep — T-DEBT Tasks 5–8 (near-complete)
**Why:** 89% done (65 Material widget hits remain across 4 frontends). Quick wins that complete an almost-finished migration.
**Action:** Finish the remaining sweeps from [`../2026-05-24-tech-debt-cleanup-material-deprecated.md`](../2026-05-24-tech-debt-cleanup-material-deprecated.md).
**Status:** 🔄 IN PROGRESS (~89% complete)

**Remaining hits (verified):**
- `neurocnl/frontend` — ~11 Material button refs
- `Neurohub/frontend` — ~9 Material button refs
- `Neurobench/frontend` — ~8 Material button refs
- `nmtk/neuro_toolkit` — ~11 Material button refs
- Neurosense — ✅ 100% complete

---

## 4. Material Icons → ZetaIcons Migration (T-ICON)
**Why:** 631 `Icons.*` references across 112 files; `zeta_flutter` is available via `nmtk_ui_core`. Priority bumped to front of queue per May 26 decision.
**Action:** Execute the sweep defined in [`../2026-05-26-material-icons-to-zeta-icons-migration.md`](../2026-05-26-material-icons-to-zeta-icons-migration.md).
**Status:** ⬜ NOT STARTED

**Verified:** 0 `ZetaIcons.*` usages in codebase. 316 `Icons.*` in `neurocnl/frontend/lib` alone.
**Note:** 49% of icons have no Zeta equivalent — strategy is Tier B (curated mapping) + Tier C1 (exemption markers for unmapped icons). Ready to execute.

---

## 5. Sentence Picker NIR Alignment (T1-10)
**Why:** Frontend CNL sentence builder still suggests forbidden keywords (MUST, STDP, sensory, motor) that the backend NIR-native compiler rejects. Causes immediate user-facing failures.
**Action:** Execute [`../2026-05-22-neurocnl-sentence-picker-nir-alignment.md`](../2026-05-22-neurocnl-sentence-picker-nir-alignment.md).
**Status:** ⬜ NOT STARTED

**Verified:** `cnl_sentence_builder_dialog.dart` still uses legacy biological templates. Backend denylist is in place — gap is frontend-only.

---

## 6. Validation Panel — Deploy Readiness (T1-11)
**Why:** Validation panel does not surface generate/preflight failures automatically. Users can reach deploy without knowing the network is undeployable.
**Action:** Complete 4-task plan in [`../2026-05-27-validation-deploy-readiness.md`](../2026-05-27-validation-deploy-readiness.md). Task 1 (audit of Layer 1 invariants) is the prerequisite.
**Status:** ⬜ NOT STARTED (specs complete; prerequisite audit not done)

**Note:** Task 1 audit doc does not exist yet — must be created before Tasks 2–4 can begin.

---

## 7. High-Yield Cleanup — Fluff Cuts Tier 2
**Why:** Reduces surface area and clarifies product scope. Non-blocking but valuable.
**Action:** Execute Tier 2 cuts from [`../archive/June 2/2026-05-fluff-cut-analysis.md`](../archive/June%202/2026-05-fluff-cut-analysis.md) — Neurohub PM chrome, neurocli/Neuro-Dream-Hand reclassification, launcher setup screen merge, nmtk_ui_core theme consolidation.
**Status:** ⬜ NOT STARTED

---

## 8. SNN / Neuromorphic Visualizer & Animation
**Why:** Studio currently has post-hoc replay and static plots but no traveling-spike topology animation, connectivity heatmap, or WebView-backed graph. The survey and ranked work plan is complete.
**Action:** Implement Tier 1 first (pure Flutter, no new deps), then Tier 2 (WebView/deck.gl skeleton). See [`2026-06-11-snn-visualizer-animation-methods.md`](2026-06-11-snn-visualizer-animation-methods.md).
**Status:** ⬜ NOT STARTED (research/spec complete; recommended first PR = T1.1 + T1.2 + T2.1 skeleton)

**Tier 1 tasks (pure Flutter, post-hoc replay):**
- T1.1 — Trained-rasters-by-class bars (on top of `spike_raster_plot.dart`)
- T1.2 — Connectivity-matrix heatmap (`connectivity_heatmap.dart`, new)
- T1.3 — Live-loss tape + replay scrubber for training (extend `loss_curve_chart.dart`)
- T1.4 — Staged Results reveal (wrap cards in `AnimatedSwitcher` + `NmtkMotionTokens.shortStep`)

**Tier 2 (WebView/deck.gl graph core — highest-risk interface, unblocks all later tiers):**
- T2.1 — `SnnGraphWebView` widget + `assets/viz/snn_graph.html` + `viz_bridge.dart` (Freezed messages)
- T2.2 — Traveling-spike pulse in 2D mode (deck.gl `LineLayer` + `ScatterplotLayer`)
- T2.3 — 2.5D/3D toggle (deck.gl `OrbitView` / three.js)

**Constraints:** No backend changes. All durations/easings via `NmtkMotionTokens`. Respect `MediaQuery.disableAnimationsOf`. `RepaintBoundary` per animated region.

---

## 9. Core Architecture & Authoring Experience
**Why:** Supports reproducible research (bundle = topology + learning rules separation) and better authoring UX (layer editor for sequential networks).
**Action:** Implement in sequence: bundle architecture → layer editor → MCP service.
**Status:** ⬜ NOT STARTED (all specs complete)

- [`../2026-05-24-nir-bundle-architecture.md`](../2026-05-24-nir-bundle-architecture.md) — T-BUNDLE
- [`../2026-05-24-layer-editor-view.md`](../2026-05-24-layer-editor-view.md) — T-LAYER
- [`../2026-05-09-mcp-service-design.md`](../2026-05-09-mcp-service-design.md) — MCP Service

---

## Permanently Deferred

- **D1 Task 3 — Update channel manifest checksums:** Blocked on finalising update distribution infrastructure. `update_service.dart` differential update logic is still a stub.
- **P0 #5 — Neurochip Validated Hardware Path:** Requires physical Teensy or PYNQ-Z2 device.

---

## Previously Completed (verified 2026-06-10/11)

| Task | Verified Files |
|------|---------------|
| Plan C2 — neurocnl Honesty | `validate.py` (verdict fallback), `export.py` (/preflight endpoint), `validation_panel.dart` (_BackendSupportBanner) |
| nir_type_check_fix | `_nir_compat.py` (safe_nir_read, NIR_READ_HAS_TYPE_CHECK, make_nir_graph), `generation.py` (safe_nir_read at lines 302, 351) |
| D3 — Golden-path CI gate | `test_golden_path_1.py` (5 steps), `golden-path.yml` (nightly + push, dual backends), `pyproject.toml` (marks, asyncio_mode) |
| D1 Task 2 — Windows signing | `sign-installer.ps1`, `build-standalone.ps1`, `CODE_SIGNING.md`, `test_windows_installer_signing.py`, `release-desktop.yml`, `ci.yml` job |
| Task 4 — Akida/PYNQ Hardware Fix | `studio_screen.dart`, `sc_neurocore_target_service.dart`, `deploy_workspace_panel.dart`, `add_hardware_target_form.dart`, `sc_neurocore_fpga_workspace.dart`, `hardware_target_dialog.dart` |
| T-DEBT Tasks 1–4 | Nengo exports deleted, Zeta theme wired, nmtk_ui_core Material components replaced |
| T-UI (shadcn → zeta_flutter) | Buttons, toasts, dialogs, command palette — all complete |
| Webtop LAN cert + HTTP→HTTPS redirect | `Dockerfile.webtop` (mkcert v1.4.4), `scripts/webtop-mkcert-startup.sh` (v2, awk splice + `exec sleep infinity`), `scripts/webtop-trust-ca.sh`, `docker-compose.webtop.yml` (ports 3030/3031, `nmtk_webtop_config` volume), `Makefile` (`webtop-trust` target) |
