# Execution Order — NeuroMorphicToolKit

This document describes the full ordering of all active issues and plans across the suite.
It combines the desktop migration rollout, the NeuroStudio UX overhaul, and the
NeuroCNL → NIR direct compilation plan into one unified dependency graph.

> **Status as of 2026-05-01**: All phases (0, A, B, C, D, E, F, G, H) are **complete**. 🎉
> Phase G is **closed — Decision D (Defer)** recorded in `Neurosense/issues/13-neurosense-relevance-evaluation.md`.

---

## How to Read This Document

- **Gate**: a task that must be fully done before anything below it starts.
- **Fan-out / parallel**: tasks that can run at the same time once their gates are met.
- `[NEW]` marks issues created in the April 2026 UX overhaul batch.
- `[CNL-NIR]` marks tasks from [`docs/cnl-to-nir-plan.md`](cnl-to-nir-plan.md).
- ✅ marks completed and archived phases.

---

## ✅ Phase 0 — Foundation Contracts (complete, archived)

All issues archived to `issues-archive/` and `nmtk_ui_core/issues-archive/`.

| What was done |
|---|
| Suite design contract (`DESIGN.md`, module briefs) |
| Shell adapter contract (`NativeSurfaceRegistry`, `WorkspaceSession`) |
| `nmtk_ui_core` shell tokens, top app bar, status primitives, module card patterns |
| Launcher workspace host (`ToolViewScreen` + `IndexedStack` warm sessions) |
| Launcher modules surface (catalog, distinct install/start/repair/error states) |

---

## ✅ Phase A — Module Shell Migration (complete, archived)

All module `10-`, `11-`, `12-` issues archived across neurocnl, Neurohub, Neurobench,
Neurosim, and Neurosense. Each module has:
- A `shell_adapter.dart` implementing the shared adapter contract
- Deep-link + restoration snapshot classes
- Native desktop screens using `nmtk_ui_core` tokens
- Registered in `NativeSurfaceRegistry`

---

---

## ✅ Phase B — Backend Compiler Track (implemented)

The CNL→NIR direct compilation work is a **pure backend track** and has no dependency on any
Flutter/UI work. It can run in parallel with Phase A and all UI phases. See
[`docs/cnl-to-nir-plan.md`](cnl-to-nir-plan.md) for full technical detail.

### ✅ B1 — I/O Role Expansion in IR

> `lowering.py` and `types.py` must be updated first so the materializer has correct IR input.

| Step | File | Change |
|------|------|--------|
| B1.1 | `neurocnl/neurocnl/ir/types.py` | Added normalized `input` / `output` population roles |
| B1.2 | `neurocnl/neurocnl/ir/lowering.py` | Lowering now maps `input/output population` sentences to explicit IR roles |

**Automated test gate:** existing lowering tests must still pass; add a test asserting that an
input-population sentence produces `role="input"` on the resulting `PopulationIR`.

### ✅ B2 — Materializer

| Step | File | Change |
|------|------|--------|
| B2.1 | `neurocnl/neurocnl/ir/materializer.py` | **[DONE]** `Materializer` added for `NetworkIR -> nir.NIRGraph` |
| B2.2 | `neurocnl/neurocnl/ir/test_materializer.py` | **[DONE]** Unit tests cover weight shape, polarity, abstract-size fallback, STDP metadata |

The materializer consumes a `NetworkIR` and produces a `nir.NIRGraph`. It must handle:
- Dimension inference for abstract populations.
- Weight synthesis (excitatory → positive arrays, inhibitory → negative).
- Scalar → vector expansion of LIF parameters.
- STDP / `LearningRuleIR` serialization into node metadata.

### ✅ B3 — Exporter and Pipeline Refactor

| Step | File | Change |
|------|------|--------|
| B3.1 | `neurocnl/neurocnl/export/nir_exporter.py` | Accepts `NetworkIR` and routes direct exports through `Materializer` |
| B3.2 | `neurocnl/neurocnl/pipeline.py` | Added direct `compile_to_nir()` path that bypasses `nengo_generator.py` |
| B3.3 | `neurocnl/neurocnl/export/test_nir_integration.py` | End-to-end coverage now asserts CNL → parse → lower → materialize → `.nir` without calling `generate()` |

**Completed on 2026-04-30:** a full CNL script now produces a valid `.nir` file through the
direct IR pipeline without calling `nengo_generator.py`.

---

## ✅ Phase C — UX Overhaul (complete)

All C1–C7 items implemented. Issues archived to `nmtk_ui_core/issues-archive/`.

| Task | What was done |
|------|---------------|
| C1 Shell chrome | `NmtkDesktopScaffold` rewritten — top bar removed, expandable sidebar replaced with 56 px compact rail, `NmtkFileActionDelegate` + back-button overlay added |
| C2 Neurosense decision | Decision D (Defer) recorded in `Neurosense/issues/13-neurosense-relevance-evaluation.md` |
| C3 Launcher integration | `modules.json` updated (`neurocnl`→NeuroStudio `required:true`; Neurohub→Share; Neurobench→Bench; Neurosense→`hasFrontend:false`). `Module.required` field added. Server-management controls hidden behind dev toggle in `ToolViewScreen`. |
| C4 Loading screen | `NmtkLoadingScreen` + `NmtkReadinessState` enum added to `nmtk_ui_core` |
| C5 Validation UX | `NmtkValidationChip` (collapsible pill) + `NmtkValidationError` added; friendly error messages; dark-mode contrast fix in `_InvariantRow` |
| C6 Gutter fix | `_buildGutter` uses `TextPainter` + `LayoutBuilder` to align gutter with wrapped lines |
| C7 Motion system | `NmtkMotionTokens`, `NmtkSharedAxisTransitionBuilder`, `NmtkTapScaleWrapper`, `NmtkStatusDot` added to `nmtk_ui_core` |

---

## ✅ Phase D — NeuroStudio Features (neurocnl + Neurosim merge) (complete)

> ✅ **D1 (neurocnl shell adoption)** is complete and archived.
> ✅ **D2 (CNL ↔ Canvas Live Bidirectional Sync)** is complete and archived.
> ✅ **D3 (Run-Sim Play Button)** is complete and archived.

`merge-cnl-sim.md` all 9 phases executed. NeuroStudio is unified at port 8000.
CNL ↔ canvas toggle live with debounced sync and loop prevention.
Animated `_PlayStopButton` replaces text button; `Cmd+Enter` shortcut wired.

| What was done |
|---|
| neurocnl + Neurosim merged into single service at port 8000 |
| `/canvas` routes added; `NeurosimHandoff` fixed to port 8000 `/canvas` path |
| `StudioViewMode` provider + CNL↔Canvas `IndexedStack` toggle with sync spinner |
| Bidirectional debounced sync with `_syncingCnlToCanvas`/`_syncingCanvasToCnl` loop guards |
| `_PlayStopButton` — animated stop icon with pulsing `CircularProgressIndicator` when running |
| `Cmd+Enter` / `Ctrl+Enter` shortcut via `CallbackShortcuts` |
| Issues 13 and 14 archived to `neurocnl/issues-archive/` |

---

## ✅ Phase E — Neurohub Reposition (Sharing Space) (complete)

> ✅ **E1 (Neurohub shell adoption)** is complete and archived.
> ✅ **C3 (launcher integration)** is complete — Neurohub labelled "Share" in `modules.json`.

### ✅ E2 — Neurohub Repositioned as Sharing Space

| What was done |
|---|
| `ENABLE_ORCHESTRATION` env flag gates `workflows` router (default `false`) |
| New `sharing.py` router: `GET /feed`, `GET /feed/unread-count`, `GET /shares` |
| `NeurohubShellSection` extended: `feed`, `myShares`, `team` added; `registry` kept for compat |
| Nav updated: Registry removed, Feed / My Shares / Team / Projects / Bundles / Settings remain |
| New screens: `FeedScreen`, `MySharesScreen`, `TeamScreen` (stub) |
| `SuiteHealthBar` and "Registry Readiness" panel removed from `DashboardScreen` |
| "Healthy Services" summary tile removed from overview strip |
| `ApiService` extended: `getFeed()`, `getFeedUnreadCount()`, `getMyShares()` |
| `modules.json` Neurohub description updated to reflect sharing identity |

---

## ✅ Phase F — Neurobench Lane (complete, archived)

All Neurobench `10-`, `11-`, `12-` issues archived to `Neurobench/issues-archive/`.

---

## ✅ Phase G — Neurosense Lane (closed — Decision D)

> ✅ **Neurosense shell adoption** (issues 10–12) is complete and archived.
> ✅ **C2 decision recorded (2026-04-30):** Option **D — Defer**.

Neurosense Python backend and FastAPI service are preserved and continue to ship.
The launcher rail entry (`hasFrontend: false` in `modules.json`) and web frontend investment
are frozen. No further Phase G work is scheduled until a Q3 2026 revisit.
See `Neurosense/issues/13-neurosense-relevance-evaluation.md` for the full rationale.

---

## ✅ Phase H — Hardware-Sensitive Lanes (complete)

> ✅ **Neurochip shell adoption** is complete and archived.
> ✅ **Neuro-Dream-Hand shell adoption** (issues 10, 11, 12) is complete and archived.

| What was done | Issue |
|---|---|
| `neurodreamhand/shell/telemetry_surface.py` — `TelemetryReviewSurface`, `SessionReview`, `RunSummary`, `DegradedCapability`; instrument-mode shell telemetry with degraded-capability probing | 10 |
| `neurodreamhand/shell/adapter.py` — `NeuroHandShellAdapter`, `ScenarioRestorer`, `ScenarioParams`, guardrail-aware deep-link encode/decode against GUARDRAILS.md bounds | 11 |
| `neurodreamhand/shell/hitl_surface.py` — `GuardedHITLSurface`, `HardwareReadiness`, `GripResult`, `DegradedMode`; grip clamped to [0, 1] before bridge dispatch; latency budget checks | 12 |
| 83 new tests across three `test_shell_*.py` files; full suite: 358/358 green | 10–12 |
| mypy strict: no issues on `neurodreamhand/shell/` | 10–12 |
| Issues 10, 11, 12 archived to `Neuro-Dream-Hand/issues-archive/` | — |

---

## Full Dependency Graph (text summary)

```
✅ Phase 0 + Phase A  (archived)
  Foundation contracts, shell tokens, launcher host, module surfaces
  All module shell-migration issues (10/11/12) across all modules
  (including Neurochip)

✅ Phase B: CNL→NIR (complete)
  B1 IR I/O roles → B2 Materializer → B3 Exporter + pipeline refactor

✅ Phase C: UX Overhaul (complete)
  C1 Shell chrome overhaul (compact rail, file actions, back button)
  C2 Neurosense decision → D (Defer)
  C3 Launcher integration (NeuroStudio, Share, Bench rail destinations)
  C4 Loading screen (NmtkLoadingScreen + NmtkReadinessState)
  C5 Validation UX (NmtkValidationChip, friendly errors, contrast fix)
  C6 Line number gutter fix (TextPainter wrap detection)
  C7 Motion system (NmtkMotionTokens, shared-axis transitions)

✅ Phase D: NeuroStudio features (complete)
  ✅ D1 neurocnl shell adoption (archived)
  ✅ D2 CNL↔Canvas live sync (archived)
  └── ✅ D3 Play button (archived)

✅ Phase E: Neurohub — sharing space (complete)
  ✅ E1 Neurohub shell adoption (archived)
  ✅ E2 Reposition as sharing (Feed, My Shares, Team; workflows gated)

✅ Phase F: Neurobench (archived)

✅ Phase G: Neurosense (closed — Decision D, Defer)

✅ Phase H: Neuro-Dream-Hand (complete)
  ✅ H1 Shell telemetry review (issue 10, archived)
  ✅ H2 Shell adapter + scenario deep-links (issue 11, archived)
  └── ✅ H3 Guarded HITL control surfaces (issue 12, archived)
```

---

## Validation Commands Reference

| Phase | Command |
|-------|---------|
| Launcher (all launcher-touching phases) | `bash scripts/run_launcher_guardrails.sh` |
| Launcher with integration | `bash scripts/run_launcher_guardrails.sh --with-integration` |
| Launcher doctor | `python3 scripts/launcher_control_service.py --doctor --json` |
| nmtk_ui_core | `cd nmtk_ui_core && flutter test` |
| nmtk launcher | `cd nmtk/neuro_toolkit && flutter test` |
| neurocnl frontend | `cd neurocnl/frontend && flutter test` |
| neurocnl backend + NIR | `cd neurocnl && PYTHONPATH=. pytest neurocnl/tests/ backend/tests/ neurosim/tests/ -v` |
| Cross-module integration | `python3 -m pytest tests/integration/test_cross_module.py` |
| E2E teensy | `python3 -m pytest tests/integration/test_teensy_e2e.py` |
| Backend smoke | `python3 scripts/backend_endpoint_smoke.py` |
