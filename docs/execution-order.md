# Execution Order — NeuroMorphicToolKit

This document describes the full ordering of all active issues and plans across the suite.
It combines the desktop migration rollout, the NeuroStudio UX overhaul, and the
NeuroCNL → NIR direct compilation plan into one unified dependency graph.

> **Status as of 2026-04-30**: Phases 0 and A are **complete and archived**.
> Phase B is now **implemented in `neurocnl`** and Phase C remains the active UX lane.

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

## Phase C — UX Overhaul (active)

All Phase C items can begin now — Phase 0 and Phase A foundation are complete.
Within Phase C, several things run in parallel.

### C1 — Shell Chrome Overhaul [NEW]

> Removes the top bar, replaces the file bar, removes the sidebar, adds back button and
> bottom-left profile/settings. **This is a gate for C4 and C5.**

Issue: [`nmtk_ui_core/issues/03-shell-chrome-overhaul.md`](../nmtk_ui_core/issues/03-shell-chrome-overhaul.md)  
Owner: F2  
Depends on: ✅ Phase 0 foundation (complete)

### C2 — Neurosense Relevance Decision [NEW]

> A human decision issue — must be resolved to determine whether Neurosense gets a Phase D
> slot or is retired. **No code changes until the decision is recorded.**

Issue: [`Neurosense/issues/13-neurosense-relevance-evaluation.md`](../Neurosense/issues/13-neurosense-relevance-evaluation.md)  
Owner: Product / engineering lead  
Depends on: `issues/06-integrate-hub-sim-bench-in-launcher.md` scope being known (i.e. C5)

### C3 — Integrate Hub, Sim, Bench in Launcher [NEW]

> Removes module/server management from the user-facing frontend. Neurohub, NeuroStudio,
> and Neurobench become first-class rail destinations.

Issue: [`issues/06-integrate-hub-sim-bench-in-launcher.md`](../issues/06-integrate-hub-sim-bench-in-launcher.md)  
Owner: F2  
Depends on: ✅ launcher workspace host + modules surface (complete), C1 (chrome overhaul)

**Runs in parallel with:** C4, C6

### C4 — Loading Screen & Backend Readiness [NEW]

> Animated loading screen that blocks entry until required backends are healthy.

Issue: [`nmtk_ui_core/issues/04-loading-screen-backend-readiness.md`](../nmtk_ui_core/issues/04-loading-screen-backend-readiness.md)  
Owner: F2  
Depends on: C1 (chrome overhaul)

**Runs in parallel with:** C3, C5, C6

### C5 — Validation UX Improvements [NEW]

> Fixes green-on-green contrast, adds collapsible dropdown, human-friendly messages,
> and standard show-errors default.

Issue: [`nmtk_ui_core/issues/05-validation-ux-improvements.md`](../nmtk_ui_core/issues/05-validation-ux-improvements.md)  
Owner: M2  
Depends on: ✅ shell tokens (complete)

**Runs in parallel with:** C3, C4, C6

### C6 — Line Number Gutter Alignment Fix [NEW]

> Fixes line-number gutter desync with editor text lines (wrap, insert/delete, zoom).

Issue: [`nmtk_ui_core/issues/06-line-number-gutter-alignment-fix.md`](../nmtk_ui_core/issues/06-line-number-gutter-alignment-fix.md)  
Owner: M2  
Depends on: ✅ neurocnl shell adapter + editor workspace (complete)

**Runs in parallel with:** C3, C4, C5

### C7 — Animation Polish & Motion System [NEW]

> Defines motion tokens; polishes route transitions, cards, play button, loading screen,
> and validation chip animations.

Issue: [`nmtk_ui_core/issues/07-animation-polish-motion-system.md`](../nmtk_ui_core/issues/07-animation-polish-motion-system.md)  
Owner: F2  
Depends on: C1 (chrome overhaul), C4 (loading screen animations), C5 (validation chip)

---

## Phase D — NeuroStudio Features (neurocnl + Neurosim merge)

> ✅ **D1 (neurocnl shell adoption)** is complete and archived.

This phase adds the NeuroStudio-specific UX features on top of the already-built
shell. It requires the merge work in [`merge-cnl-sim.md`](../merge-cnl-sim.md)
(phases 0–9) to be executed before D2 and D3.

### D2 — CNL ↔ Canvas Live Bidirectional Sync [NEW]

> Adds a toggle between the CNL text view and the canvas graph view. Changes in one live-update
> the other without any manual compile step.

Issue: [`neurocnl/issues/13-neurostudio-cnl-canvas-live-sync.md`](../neurocnl/issues/13-neurostudio-cnl-canvas-live-sync.md)  
Owner: M2  
Depends on: D1 shell adapter (issue 11), neurocnl/12, and the merge-cnl-sim.md execution

### D3 — Run-Sim Play Button [NEW]

> Replaces the text run button with an animated play/stop button inline in the pipeline toolbar.
> Supports `Cmd+Enter` shortcut. Disabled when validation errors exist.

Issue: [`neurocnl/issues/14-neurostudio-run-sim-play-button.md`](../neurocnl/issues/14-neurostudio-run-sim-play-button.md)  
Owner: M2  
Depends on: D2 (CNL ↔ canvas sync, which establishes the sim provider contract)

---

## Phase E — Neurohub Reposition (Sharing Space)

> ✅ **E1 (Neurohub shell adoption)** is complete and archived.

Depends on C3 (launcher integration) scoping what the Neurohub surface is allowed to keep.

### E2 — Neurohub Repositioned as Sharing Space [NEW]

> Removes module-orchestration surfaces. Adds Feed, My Shares, and Team stub.
> Renames the rail entry to "Share".

Issue: [`issues/05-neurohub-reposition-as-sharing-space.md`](../issues/05-neurohub-reposition-as-sharing-space.md)  
Owner: M4  
Depends on: C3 (launcher integration), ✅ E1 shell adoption (complete)

---

## ✅ Phase F — Neurobench Lane (complete, archived)

All Neurobench `10-`, `11-`, `12-` issues archived to `Neurobench/issues-archive/`.

---

## Phase G — Neurosense Lane (conditional on C2 decision)

> **Gate: C2 must produce a decision before further Phase G work starts.**

> ✅ **Neurosense shell adoption** (issues 10–12) is complete and archived.
> The remaining question is the **strategic role** of Neurosense going forward.

If the decision from C2 is **Option A (Keep, integrate)**:
Create follow-up issues for any Neurosense-specific UX work beyond what is already built.

If the decision is **Option C (Retire)**, follow the archival procedure in Phase 9 of
[`merge-cnl-sim.md`](../merge-cnl-sim.md) applied to the Neurosense submodule.

If the decision is **Option B (Background)** or **D (Defer)**, no additional Phase G work is scheduled.

---

## Phase H — Hardware-Sensitive Lanes

Start only after long-running job patterns, degraded-state UX, and capability reporting from
Phase D and F are proven.

> ✅ **Neurochip shell adoption** is complete and archived.

| Issue folder | Owner |
|---|---|
| `Neuro-Dream-Hand/issues/*.md` | M7 |

---

## Full Dependency Graph (text summary)

```
✅ Phase 0 + Phase A  (archived)
  Foundation contracts, shell tokens, launcher host, module surfaces
  All module shell-migration issues (10/11/12) across all modules
  (including Neurochip)

Phase B: CNL→NIR (active — pure backend, independent)
  B1 IR I/O roles (types.py + lowering.py)
  └── B2 Materializer (materializer.py + tests)
        └── B3 Exporter + pipeline refactor + integration tests

Phase C: UX Overhaul (active)
  C1 Shell chrome overhaul [NEW]  ← gate for C4, C7
  C3 Integrate hub/sim/bench in launcher [NEW]  ← after C1
  C4 Loading screen [NEW]  ← after C1
  C5 Validation UX [NEW]
  C6 Line number fix [NEW]
  C7 Animation polish [NEW]  ← after C1, C4, C5

Phase D: NeuroStudio features (merge-cnl-sim.md first)
  ✅ D1 neurocnl shell adoption (archived)
  D2 CNL↔Canvas live sync [NEW]
  └── D3 Play button [NEW]

Phase E: Neurohub (sharing space)
  ✅ E1 Neurohub shell adoption (archived)
  E2 Reposition as sharing [NEW]  ← after C3

✅ Phase F: Neurobench (archived)

Phase G: Neurosense (C2 decision required)
  ✅ Shell adoption issues (archived)
  Follow-up issues TBD after C2 decision

Phase H: Neuro-Dream-Hand (last)
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
