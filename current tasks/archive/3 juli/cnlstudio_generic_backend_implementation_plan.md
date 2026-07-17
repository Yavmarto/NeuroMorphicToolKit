# Goal: Close the Generic Backend/Node-Support Gaps Needed to Replicate the 42 `paper/` Notebooks

## Verified Implementation Status (2026-07-04)

**Overall: DONE.** All 8 phases in this plan (the doc defines 8, not 9) are implemented in the `neurocnl` submodule at commit `dbb0944b` ("Harden NIR backend/deploy-target support (Phases A-H)", dated Sat Jul 4 07:24:56 2026), which is the submodule commit the outer repo's working tree currently has checked out. This landed the day after the plan was written and matches it near line-for-line, including the exact bug descriptions cited in the plan (e.g. the `CubaLIF`/`.tau` crash, the `rockpool_io` order-dependent infinite loop).

- **Phase 1 (Backend support-table completeness):** DONE. `neurocnl/runtime/nir_support.py` now has full `_BACKEND_NIR_SUPPORT` entries for `brian2`, `pynn`, `lava`, `rockpool`, `sinabs`, `nengo`, `akida`, `sc_neurocore_fpga` (previously only 3 backends). `lava_sim`/`Affine` verdict changed from `"unsupported"` to `"approximate"` as specified. `test_nir_support.py` extended (330 lines added per `git show --stat dbb0944b`).
- **Phase 2 (Wire classification into codegen router):** DONE. `backend/app/routers/notebook.py` calls `classify_nir_graph`/`_flatten_and_classify` before the dispatch chain; `support_level`/`diagnostics` fields added to response models (lines ~67-68, 2108-2109, 2123-2124, confirmed via grep).
- **Phase 3 (Generic `cnl.*` flattening utility):** DONE. `neurocnl/runtime/cnl_flatten.py` exists with `flatten_cnl_ops(graph) -> tuple[nir.NIRGraph, list[str]]` matching the exact signature specified; `test_cnl_flatten.py` present (148 lines).
- **Phase 4 (Self-loop-tolerant topology helper):** DONE. `neurocnl/runtime/nir_topology.py` exists with `classify_topology()` and `linearize()`; `rockpool_io.py` and `sinabs_io.py` both import and use it, replacing the old hand-rolled adjacency walks.
- **Phase 5 (Integrate flatten + topology at dispatch):** DONE. `notebook.py` has `_CNL_FLATTEN_TARGETS` (data-driven, scoped to `brian2`/`sinabs`/`rockpool`/`pynn`/`nengo`/`akida`, deliberately excluding `lava`/`lava_sim`/`sc_neurocore_*` per an explicit inline rationale) and `_graph_needs_cnl_flatten`/`_flatten_and_classify` helpers wired before codegen.
- **Phase 6 (Silent-skip → loud-fail hardening):** DONE. `neurocnl/converter/_diagnostics.py` provides `raise_unsupported_node`; it's called from `pynn_io.py:118`, `brian2_io.py:106`, `lava_io.py:111,214`, and `notebook.py:1058` (Akida path), matching the plan's file list exactly.
- **Phase 7 (Deploy-target UI wiring):** DONE. `backend/app/routers/deploy_targets.py` (`GET /deploy-targets`, registered in `main.py`) sources from `nir_support.list_supported_backends()`. Flutter side has `codegen_preview_panel.dart`, `support_level_badge.dart`, `deploy_targets_provider.dart`; `deploy_workspace_panel.dart` now derives `isSimulatorTarget` from the fetched `kind` field instead of a hardcoded string check. `simulators.py`'s `_KNOWN_BACKENDS`/`_KNOWN_PREFLIGHT_BACKENDS` now derive from `list_simulator_backends()` (a `nir_support.py` accessor) rather than literal sets.
- **Phase 8 (`lava_sim`/`Affine` real runtime support):** DONE. `lava_simulator.py` includes `Affine` in its dispatch set and constructs `Dense(weights=...)`; `lava_io.py` enforces the zero-bias constraint with an explicit error message; `test_lava_simulator.py` extended (78 lines added).

**Caveats:**
- Could not execute the new test suites in this environment — `pytest` collection fails on an unrelated, pre-existing broken `matplotlib`/`nengo` install in the local Python environment (`ImportError: cannot import name '_c_internal_utils'`), not on anything in this diff. The commit message itself claims a full regression sweep was run (via git-stash comparison) elsewhere.
- Explicitly-deferred items (SpiNNaker2 wiring, `lava.lib.dl.slayer` path, Spyx/Xylo/Norse backends) remain out of scope as the plan itself specifies — not gaps in this phase set.

---

**Date:** 3 July 2026
**Scope:** Follow-up implementation plan for the gaps identified in [`../16 june/cnlstudio_notebook_analysis.md`](../16%20june/cnlstudio_notebook_analysis.md) and [`../16 june/cnlstudio_notebook_analysis_extended.md`](../16%20june/cnlstudio_notebook_analysis_extended.md) (42 notebooks across `paper/01_lif`, `paper/02_cnn`, `paper/03_rnn`).
**Constraint:** Every item below is generic and reusable across any model/graph — nothing notebook-specific. Ground-up new deploy backends (Spyx, Xylo, Norse) have zero existing scaffolding to build on and are listed as backlog only, not designed here.

This plan closes the backend/converter/classification gaps that block CNLStudio from confidently replicating the notebook set. The reverse-engineering audit found the Model-canvas node palette is already complete — every node type the notebooks need (`Input`, `Output`, `Linear`, `Affine`, `Conv2d`, `Flatten`, `IF`, `LIF`, `CubaLIF`, `LI`, `AvgPool2d`, `SumPool2d`, `Delay`, `Scale`, `cnl.Synaptic`, `cnl.RSynaptic`, `cnl.RLeaky`, `cnl.Leaky`, `cnl.BatchNorm1d`, `cnl.Dropout`) exists in `nir_types_provider.dart` / `nir_graph_serializer.py` / `cnl_nodes.py`. The real gap is entirely on the backend side: 9 of 11 deploy targets have no formal support verdict, `cnl.*` custom ops silently break or crash on 5 of 6 non-native converters, three converters silently drop unrecognized nodes instead of failing loudly, and the Flutter deploy UI has 5 dead panels for real, working backends.

All facts below were verified directly against source: `neurocnl/neurocnl/runtime/nir_support.py` read in full; `neurocnl/backend/app/routers/notebook.py`'s dispatch chain and `_safe_io_call`, and `neurocnl/backend/app/routers/simulators.py`'s `_KNOWN_BACKENDS`/`_KNOWN_PREFLIGHT_BACKENDS`, grepped and confirmed at the line numbers cited.

## Key Mechanism Already In Place

`neurocnl/neurocnl/runtime/nir_support.py` is the single source of truth for per-backend node support: `COMPLETE_PRIMITIVE_SET` (lines 49-77) lists every node type that must be classified; `_BACKEND_NIR_SUPPORT` (79-179) currently classifies only `sc_neurocore_sim`, `lava_sim`, `snntorch_sim`; `classify_nir_graph()` (219-296) looks up `type(node).__name__` per backend and default-denies unknown types. This is wired into `neurocnl/backend/app/routers/simulators.py`'s `/simulators/preflight` and `/simulators/run` endpoints (`_KNOWN_BACKENDS` line 222, `_KNOWN_PREFLIGHT_BACKENDS` line 639) — but **not** into `neurocnl/backend/app/routers/notebook.py`'s codegen dispatch (`elif target == ...` chain, lines 1778-1807), which is what all 9 non-simulator deploy targets (`akida`, `brian2`, `sinabs`, `rockpool`, `pynn`, `nengo`, `lava`, `sc_neurocore_fpga`) actually go through. So today zero codegen targets get a preflight verdict at all — this single gap is the root cause of the "6 unclassified backends" problem raised in the extended report.

Also confirmed: `_safe_io_call` (`notebook.py:1009`) catches any converter exception and silently replaces it with a scaffold-comment fallback, logging only server-side — so even converters that already raise loudly today (`sinabs_io.py`, `nengo_io.py`) don't currently surface that failure to the end user.

## Open Questions

1. **SpiNNaker2 wiring scope:** Substantial real backend scaffolding already exists in `Neurochip`/`Neurosim`/`Neurobench`, reachable via `suite_api`, but there is no existing NIR → Neurosim-`CanvasGraph` converter (the transport layer exists; the graph-schema adapter doesn't). This is a different risk class (cross-app schema dependency) than the phases below, which are entirely internal to `neurocnl/`. Recommend a dedicated investigation spike before scheduling it as a phase.
2. **`lava.lib.dl.slayer` path:** `paper/nir_to_lava.py::import_from_nir_to_lava_dl` (lines 175-591) has real, reusable logic including genuine recurrent-subgraph folding, but targets a training-oriented API distinct from `lava_simulator.py`'s runtime API. Worth a future phase, but not required to unblock any notebook beyond what Phase 8 below already covers for the plain-LIF case — deferred as backlog.

## Proposed Changes

---

### Phase 1: Backend Support-Table Completeness

Give every deploy-catalog backend a formal exact/approximate/unsupported verdict per node type, and fix the one known-wrong verdict.

#### [MODIFY] [neurocnl/neurocnl/runtime/nir_support.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/runtime/nir_support.py)
Add `_BACKEND_NIR_SUPPORT` entries for `brian2`, `sinabs`, `rockpool`, `pynn`, `nengo`, `akida`, `lava` (hardware codegen target, distinct from `lava_sim`), and `sc_neurocore_fpga`, derived from what each converter module actually implements today (e.g. `rockpool_io.py` only dispatches `Input`/`Output`/`Linear`/`LIF`/`CubaLIF` → those exact/approximate, rest unsupported; `sinabs_io.py`'s `_SUPPORTED = (Linear, Affine, LIF, IF)` maps directly). Also change `lava_sim`'s `Affine` verdict from `"unsupported"` to `"approximate"` (a real `Affine → Dense` mapping already exists in `paper/nir_to_lava.py`, subject to a zero-bias constraint — see Phase 8). Extend `_BACKEND_DISPLAY_NAMES` with the new backend labels.

#### [MODIFY] [neurocnl/neurocnl/runtime/test_nir_support.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/runtime/test_nir_support.py)
Extend the existing completeness assertion to cover the new backend keys against `COMPLETE_PRIMITIVE_SET`.

---

### Phase 2: Wire Classification into the Codegen Router

Make every codegen target — not just the 3 simulator-runtime backends — show the user a real support verdict, using the table from Phase 1.

#### [MODIFY] [neurocnl/backend/app/routers/notebook.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/backend/app/routers/notebook.py)
Call `classify_nir_graph(graph, target)` once, immediately before the `elif target == ...` dispatch chain (~line 1778), for every codegen target — reusing the exact function `simulators.py` already calls. Add a markdown warning cell when `level != "exact"`, listing `classification.diagnostics`. Extend the response model (`NotebookEntry`/`GenerateV2Response`) with `support_level`/`diagnostics` fields so the Flutter UI can render a badge instead of only a buried markdown cell.

---

### Phase 3: Generic `cnl.*` Flattening Utility

Provide one reusable pass that rewrites CNLStudio-internal ops into standard NIR primitives, so any converter that doesn't natively understand `cnl.*` can consume a flattened graph instead of needing bespoke per-type branches.

#### [NEW] [neurocnl/neurocnl/runtime/cnl_flatten.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/runtime/cnl_flatten.py)
`flatten_cnl_ops(graph: nir.NIRGraph) -> tuple[nir.NIRGraph, list[str]]`. Maps `Leaky` → `nir.LIF` and `Synaptic` → `nir.CubaLIF` (direct 1:1 parameter mappings). Maps `RSynaptic`/`RLeaky` → a `CubaLIF`/`LIF` node plus a `nir.Linear` self-loop edge in the same flat graph, matching `nengo_io.py`'s existing documented expectation (lines 120-144, 247-256) that nothing upstream currently satisfies. Since `cnl.RSynaptic`/`RLeaky` carry no trained recurrent-weight field today (`snntorch_simulator.py` constructs `snntorch.RSynaptic` fresh with snnTorch's own init, no `load_state_dict` call) the synthesized recurrent weight is structural-only, documented via a returned diagnostic string — parity with existing behavior, not a new limitation. Maps `BatchNorm1d` → `nir.Affine` folded from running stats when present, else passthrough with a diagnostic. Maps `Dropout` → passthrough (eval-mode no-op). Idempotent and a no-op on graphs with zero `cnl.*` nodes.

#### [NEW] [neurocnl/neurocnl/runtime/test_cnl_flatten.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/runtime/test_cnl_flatten.py)
Unit tests against synthetic `nir.NIRGraph` fixtures covering each mapped type plus the no-op case.

---

### Phase 4: Generic Self-Loop-Tolerant Topology Helper

Replace two independently-buggy adjacency walks with one shared graph-shape classifier that tolerates a single self-loop — the shape Phase 3's flatten produces, and also the shape any natively-authored recurrent NIR graph would have.

#### [NEW] [neurocnl/neurocnl/runtime/nir_topology.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/runtime/nir_topology.py)
`classify_topology(graph) -> Literal["linear", "linear_with_recurrence", "branching"]` and `linearize(graph) -> list[str]` (execution order; for `"linear_with_recurrence"`, returns the forward chain with the recurrent partner tagged separately rather than silently misordered).

#### [NEW] [neurocnl/neurocnl/runtime/test_nir_topology.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/runtime/test_nir_topology.py)
Unit tests covering a plain chain, a chain with one self-loop, and a genuinely branching graph.

#### [MODIFY] [neurocnl/neurocnl/converter/rockpool_io.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/converter/rockpool_io.py)
Replace the hand-rolled single-path adjacency walk (`while curr in adj and adj[curr]: curr = adj[curr][0]`, ~lines 119-123) with a call into `nir_topology.linearize`.

#### [MODIFY] [neurocnl/neurocnl/converter/sinabs_io.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/converter/sinabs_io.py)
Replace the manual branching-rejection check (~lines 246-280) with `nir_topology.classify_topology`; keep rejecting true branching, stop conflating a self-loop with branching.

---

### Phase 5: Integrate Flatten + Topology at the Dispatch Site

Actually apply Phases 3 and 4 at the one dispatch site so `cnl.*`-bearing graphs stop hitting `raise ValueError`/`NotImplementedError`/silent-skip in the 6 gap converters.

#### [MODIFY] [neurocnl/backend/app/routers/notebook.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/backend/app/routers/notebook.py)
At the same dispatch block from Phase 2: if the graph contains any `cnl.*` node and the target backend's Phase-1 table doesn't mark that type `"exact"`, call `flatten_cnl_ops(graph)` before handing the graph to `Brian2IO`/`SinabsIO`/`RockpoolIO`/`PyNNIO`/`NengoIO`/`_generate_akida_code`. Gate is data-driven off the Phase 1 table, not hardcoded per backend.

---

### Phase 6: Silent-Skip → Loud-Fail Hardening

Make converters that currently drop unrecognized node types silently instead fail loudly and visibly, matching the pattern `sinabs_io.py`/`nengo_io.py` already use. **Must land after Phase 5** — shipping this first would hard-fail every `cnl.*`-bearing graph on these targets where today it silently (wrongly) produces something; Phase 5 converts "silently wrong" into "correct" first.

#### [NEW] [neurocnl/neurocnl/converter/_diagnostics.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/converter/_diagnostics.py)
One shared `raise_unsupported_node(node, converter_name, supported_types) -> NoReturn` helper, producing the same message shape `nengo_io.py` already uses.

#### [MODIFY] [neurocnl/neurocnl/converter/brian2_io.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/converter/brian2_io.py)
Add `else: raise_unsupported_node(...)` to the node-dispatch loops (~lines 181-200) that currently fall through silently.

#### [MODIFY] [neurocnl/neurocnl/converter/pynn_io.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/converter/pynn_io.py)
Same fix at the `elif isinstance(node, nir.Linear): pass` fallthrough (~line 108).

#### [MODIFY] [neurocnl/neurocnl/converter/lava_io.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/converter/lava_io.py)
Same fix in `from_nir` (~line 189) and `to_runtime_payload` (~line 178).

#### [MODIFY] [neurocnl/backend/app/routers/notebook.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/backend/app/routers/notebook.py)
Add the same loud-fail branch to `_generate_akida_code` (~line 894 onward). Also change `_safe_io_call` (line 1009) so the caught exception's message is surfaced into the generated notebook as an error cell in addition to falling back to scaffold code, instead of only logging server-side — without this, the loud failures above stay invisible to the user.

---

### Phase 7: Deploy-Target UI Wiring + Single Source of Truth

5 of 11 catalog targets (`brian2`, `sinabs`, `rockpool`, `pynn`, `nengo`) render an empty panel today despite having real backend converters.

#### [NEW] [neurocnl/backend/app/routers/deploy_targets.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/backend/app/routers/deploy_targets.py)
`GET /deploy-targets` endpoint returning `[{id, label, kind, support_summary}]`, sourced from `nir_support.list_supported_backends()`.

#### [MODIFY] [neurocnl/frontend/lib/screens/studio/deploy/deploy_target_workspace.dart](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/screens/studio/deploy/deploy_target_workspace.dart)
Add one shared `CodegenPreviewPanel` widget (not 5 bespoke panels) showing the Phase 2 support badge, diagnostics, and generated code preview. Wire the 5 currently-empty targets to it instead of `_ => SizedBox.shrink()`.

#### [MODIFY] [neurocnl/frontend/lib/screens/studio/deploy/deploy_workspace_panel.dart](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/screens/studio/deploy/deploy_workspace_panel.dart)
Replace the hardcoded `isSimulatorTarget` string-literal check (lines 21-24) with a derivation from the fetched target `kind` field.

#### [MODIFY] [neurocnl/backend/app/routers/simulators.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/backend/app/routers/simulators.py)
Replace the duplicated `_KNOWN_BACKENDS` (line 222) / `_KNOWN_PREFLIGHT_BACKENDS` (line 639) literal sets with `set(nir_support.list_supported_backends())`.

---

### Phase 8: `lava_sim` / `Affine` Real Runtime Support

Back Phase 1's `"approximate"` reclassification of `lava_sim`/`Affine` with an actual runtime mapping, since `lava_simulator.py` today only dispatches `nir.LIF | nir.CubaLIF`.

#### [MODIFY] [neurocnl/neurocnl/runtime/lava_simulator.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/runtime/lava_simulator.py)
Port the proven `Affine → lava.proc.dense.Dense` mapping from `paper/nir_to_lava.py::_nir_node_to_lava` (lines 96-99), enforcing the same zero-bias constraint as a clear runtime error rather than an unstated assumption.

#### [MODIFY] [neurocnl/neurocnl/runtime/test_lava_simulator.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/runtime/test_lava_simulator.py)
Add coverage for an `Affine → LIF` graph.

---

## Phase Dependencies

```
1 (support tables) ──┬──> 2 (wire classifier into notebook.py) ──> 7 (UI wiring, needs 1+2)
                      │
                      └──> 8 (lava_sim Affine runtime, needs 1's data change)

3 (cnl flatten) ──┐
                  ├──> 5 (integrate 3+4 at dispatch, needs 1 for gating) ──> 6 (loud-fail hardening, must follow 5)
4 (topology) ─────┘
```

## Explicitly Out of Scope (Backlog Only)

- **Spyx / Xylo / Norse backends** — zero existing converter/backend code for any of the three; net-new construction, not extension of existing scaffolding.
- **`lava.lib.dl.slayer` Conv2d/pooling/recurrent-subgraph path** — real and reusable logic exists (`paper/nir_to_lava.py`, lines 175-591), but targets a different API than `lava_simulator.py` and isn't required beyond what Phase 8 covers.
- **SpiNNaker2 deploy-target wiring** — real backend scaffolding exists in `Neurochip`/`Neurosim`/`Neurobench` and is reachable via `suite_api`, but no NIR → Neurosim-`CanvasGraph` converter exists. Needs a dedicated investigation spike (cross-app schema dependency) before it can be scoped as a phase.

## Verification Plan

### Automated Tests
- Phase 1: existing `nir_support.py` completeness test fails until every new backend key covers `COMPLETE_PRIMITIVE_SET`, then passes.
- Phase 3/4: new unit tests against synthetic `nir.NIRGraph` fixtures with `RSynaptic`/`Synaptic`/self-loops — assert `flatten_cnl_ops` output re-classifies as exact/approximate on the target's Phase-1 table, and `linearize`/`classify_topology` correctly distinguish a self-loop from real branching.
- Phase 5: run the existing Braille NIR fixture (`paper/03_rnn/data/braille_noDelay_*.nir`, and `neurocnl/backend/tests/test_notebook_codegen.py`'s `_braille_nir_graph()`) through `rockpool`/`brian2`/`pynn`/`nengo`/`akida` codegen and confirm no crash and no silent drop.
- Phase 8: new `test_lava_simulator.py` coverage for `Affine → LIF`.

### Manual Verification
- Phase 2: call the notebook-generation endpoint targeting `nengo`/`rockpool`/`sinabs` and confirm the response carries `support_level`/`diagnostics` and the generated notebook shows a warning cell when not exact.
- Phase 6: feed a graph with a genuinely unsupported node type to `brian2`/`pynn`/`lava`/`akida` and confirm the generated notebook shows an explicit error cell, not silent scaffold code.
- Phase 7: open the Studio Hardware Deployment step, select each of the 5 previously-empty targets, confirm the shared panel renders code + badge instead of a blank box.
- Phase 8: run `lif_lava.ipynb`'s `Affine → LIF` graph through `lava_sim` via `/simulators/run` and confirm it returns `"approximate"` (not `"unsupported"`) and produces output.
