# NMTK Master Task Order
## Active Scope: `CNL -> IR -> NIR`

> **Plan maintenance**: this plan needs to be updated after each meaningful task change.
> **Update style**: keep the work-done note very short and concise.
> **Latest concise update**: T1-2 and T1-3 closed. Canonical editor sync now drives the main CNL→canvas path, `generate_cnl_from_nir()` is public from `neurocnl.__init__`, and `.nir` upload now round-trips through a diagnostics-rich NIR→CNL bridge.

> **Updated**: 2026-05-14  
> **Scope decision**: Active product support is now limited to authoring, validating, and exporting `CNL -> IR -> NIR`.
>
> **Sources merged**:
> - `docs/current tasks/neurocnl_status_and_priorities.md`
> - `docs/unified_toolkit_architecture.md`
> - `docs/current tasks/2026-05-10-neurocnl-workspace-simulation-persistence-plan.md`
> - `docs/current tasks/2026-05-13-quick-wins-and-bugfixes.md`
> - `docs/current tasks/2026-05-13-cnl-matrix-and-phase-2-plan.md`
> - `docs/current tasks/2026-05-13-clean-bidirectional-cnl-canvas-plan.md`

---

## Scope Rules

- Keep in the active queue: CNL authoring, validation, workspace/file flows, NIR lowering, NIR export, and NIR-backed graph/editor coherence.
- Remove from the active queue: legacy execution backends, runtime-specific fixes, training UI, benchmark-first APIs, hardware deployment, launcher/runtime work, and release-readiness tracking for non-NIR targets.
- Historical docs for those broader workflows may remain in the repo, but they are not part of the current delivery order.

---

## Current Status

- Confirmed complete: direct `CNL -> IR -> NIR` export exists for the currently supported subset.
- Confirmed complete: NIR export still fails closed for unsupported concepts instead of exporting dishonestly.
- Confirmed complete: actionable validation/export diagnostics are already normalized enough to support UI cleanup work.
- Remaining active gaps are now concentrated in four areas:
  1. Workspace/file persistence around NIR artifacts
  2. Validation copy and label readability
  3. Honest expansion of the supported NIR subset
  4. One canonical NIR-backed graph state across editor and canvas

---

## Tier 0 — Immediate Work

### T0-A: Workspace File I/O and NIR Artifact Persistence
**Status**: Active.
**Why first**: Reliable save/open behavior is foundational, and cached NIR artifacts should stay attached to the file that produced them.

| Phase | Task | Key files |
|-------|------|-----------|
| 1 | Implement real native `open` / `save as` for `.cnl` files | `platform_helper*.dart`, `import_text_file_picker*.dart` |
| 2 | Introduce `.neurocnl-workspace.json` round-trip support | `workspace_file.dart`, `workspace_provider.dart` |
| 3 | Scope cached NIR export results per file and restore them on file switch | `pipeline_provider.dart`, workspace model |
| 4 | Add rename + comparison panel in Studio UI | `studio_screen.dart` |

**Exit criteria**: Desktop load imports `.cnl`; save writes to a user-chosen path; workspace reopen restores tabs and cached NIR results.

---

### T0-B: Actionable Error Diagnostics
**Status**: Complete on 2026-05-12.
**Why now**: This is already implemented enough to treat as a baseline for UI cleanup and NIR-only flows.

1. Keep one shared error schema (`code`, `message`, `hint`, `examples`, `line`, `raw`)
2. Preserve it across parse, validate, generate, and export routes
3. Keep Layer 1 and Layer 2 guidance prescriptive instead of collapsing to plain strings
4. Keep tests asserting payload shape, not just failure presence

---

### T0-C: Quick Wins and Bugfixes
**Status**: Active / High Priority. Items 2–5 complete. Item 1 profiling evidence still outstanding.
**Why now**: These are the highest-signal usability issues still relevant to a `CNL -> NIR` product.

1. **Workspace Load Performance**: profile the load path and add the "Obsidian Flow" loading treatment when delay is structural. *(loader + overlay exist, profiling evidence not yet captured)*
2. **Template Popup**: use a normal modal/popup for template selection. ✅ complete
3. **Layer 1 Validation Copy Cleanup**: keep the success text once, not twice, and render labels without underscores. ✅ complete
4. **Label Readability**: replace underscores with whitespace in Layer 1 and Layer 2 labels throughout the UI. ✅ complete
5. **CNL-Canvas Sync Regression**: stop comment stripping and unwanted text rewrites during round-trip editing. ✅ complete — comment preservation implemented in sync_provider.dart; explicit comment-preservation and no-op round-trip regression tests added in test/providers/canvas/sync_provider_test.dart.

---

### T0-D: Resolve STP NIR Type Mismatch and Round-Trip Failure
**Status**: Complete on 2026-05-13.
**Why now**: STP templates still expose weak spots in the supported `CNL -> NIR` path.

1. Fix NIR export dimensionality for neuron-to-neuron connections in `neurocnl/export/nir_exporter.py` ✅ — covered by nir_integration and materializer tests.
2. Keep NIR graph connectivity aligned with actual neuron counts when `.neurons` is used ✅ — serializer/materializer coverage green.
3. Fix the editor/canvas synchronization failure on the STP template ✅ — root cause was the CNL parser rejecting population-level threshold/refractory/decay sentences; fixed in `neurocnl/cnl/cnl_parser.py` (`_THRESHOLD_PATTERNS`, `_REFRACTORY_PATTERNS`, `_DECAY_PATTERNS` now accept arbitrary named populations). STP template parse-cnl round-trip test added in `neurosim/tests/routers/test_generation.py`.
4. Add end-to-end verification for the STP NIR export path and round-trip behavior ✅ — `test_nir_capability_templates_exercise_t1_4_semantics` and `test_nir_capability_templates_generate_without_backend_selection_errors` now pass cleanly for both `visual_homeostasis_gate` and `dopamine_stp_decision` templates.

---

### T0-E: Matrix-Native CNL on Top of IR
**Status**: Complete on 2026-05-13.
**Why now**: This locks the long-term compiler architecture before more feature work accumulates around metadata-only escape hatches.

1. Keep `NetworkIR` as the permanent semantic boundary between CNL authoring and NIR emission
2. Add first-class CNL sentence families for explicit dense matrices, matrix shape clauses, and shape inference when source/target sizes make the matrix dimensions deterministic
3. Lower matrix-native CNL directly into exact `ConnectionIR.weight` tensors instead of relying on heuristic resizing or hidden-only metadata
4. Keep the NIR materializer/exporter as the stable dumb pipe for explicit weights
5. Reserve Phase 2 for a future high-level expander that emits `NetworkIR`, not `nir.NIRGraph`, so solver-backed math generation can be inserted later without rewriting NIR plumbing

**Primary plan doc**: `docs/current tasks/2026-05-13-cnl-matrix-and-phase-2-plan.md`
**Exit criteria**: natural-language matrix authoring survives `CNL -> IR -> NIR` exactly; ambiguous shapes fail with structured diagnostics; future high-level expansion has a clean pre-NIR insertion point.

---

## Tier 1 — Core NIR Completeness

### T1-1: Expand NIR Semantic Coverage
**Status**: Active.
**Priority order**:

1. `short_term_plasticity`
2. `lateral_inhibition`
3. `homeostatic_plasticity`
4. `neuromodulation`

For each concept: update lowering in `nir_exporter.py`, add tests, and keep unsupported cases fail-closed.

---

### T1-2: Make NIR the Canonical Studio Graph Model
**Status**: Complete on 2026-05-14.

1. Treat the editor/canvas graph as one NIR-backed state instead of parallel ad-hoc models ✅
2. Make CNL edits compile into that same canonical graph state ✅
3. Preserve advisory semantics and unsupported-node diagnostics in the shared graph model ✅
4. Document the invariant explicitly: inside the app, NIR-backed graph state is canonical and CNL is the readable representation ✅

**Primary plan doc**: `docs/current tasks/2026-05-13-clean-bidirectional-cnl-canvas-plan.md`

**Exit criteria**: editor, canvas, and export all describe the same underlying graph without silent drift.

---

### T1-3: NIR -> CNL Translation Bridge
**Status**: Complete on 2026-05-14.

1. Build an explicit `NIRGraph -> NetworkIR -> CNL text` path ✅
2. Add a supported `generate_cnl_from_nir(...)` surface for `.nir` uploads and graph summaries ✅
3. Reject or annotate unsupported NIR primitives with structured diagnostics instead of hallucinating exact CNL semantics ✅
4. Add semantic round-trip tests for `CNL -> NIR -> CNL` and `NIR -> CNL -> IR` ✅

---

### T1-4: Public `compile_to_nir()` Surface
**Status**: Complete on 2026-05-14.

1. Add a thin documented `compile_to_nir(spec: str) -> NIRGraph | artifact` entrypoint ✅ — `neurocnl/compile.py`; returns `nir.NIRGraph` directly; optional `save_to` writes `.nir` file.
2. Make it the primary public-facing API in docs and examples ✅ — exported from `neurocnl.__init__` (`compile_to_nir`, `CompileError`, `Diagnostic`).
3. Keep the contract fail-closed and diagnostics-rich ✅ — `CompileError` carries a `list[Diagnostic]` with `stage`, `code`, `message`, `line`, `raw`, `hint` per failure; 40 tests cover all five pipeline stages.

---

## Tier 2 — Later, If Tier 1 Stabilizes

### T2-1: Quantization-Aware Lowering
- Add workflow-complete quantization support only where current NIR-adjacent targets actually require it.

### T2-2: Hybrid SNN-ANN Node Type Tags
- Add `node_type: "snn" | "ann"` tagging in NIR routing logic once the canonical graph model is stable.

### T2-3: Multi-Chip Partitioning
- Revisit only after single-graph semantics and round-trip translation are stable.

---

## Do Not Prioritize Now

| Task | Reason |
|------|--------|
| Legacy execution-backend work | Outside the active `CNL -> NIR` support boundary |
| Runtime-specific fixes | Outside the active `CNL -> NIR` support boundary |
| Training UI and framework adapters | Outside the active `CNL -> NIR` support boundary |
| Hardware deployment and release-readiness work | Outside the active `CNL -> NIR` support boundary |
| Benchmark-first APIs | Outside the active `CNL -> NIR` support boundary |
| LLM-assisted CNL | Still too early |
| WASM browser runtime | Still not viable for the workload |

---

## Execution Summary

| Tier | ID | Task | Status | Blocked by |
|------|----|------|--------|-----------|
| 0 | T0-A | Workspace file I/O and NIR artifact persistence | Active | — |
| 0 | T0-B | Actionable error diagnostics | Complete | — |
| 0 | T0-C | Quick wins and bugfixes | Active | — |
| 0 | T0-D | STP NIR type mismatch and round-trip fix | Complete | — |
| 0 | T0-E | Matrix-native CNL on top of IR | Complete | — |
| 1 | T1-1 | NIR semantic coverage expansion | Active | — |
| 1 | T1-2 | NIR as canonical Studio graph model | Complete | — |
| 1 | T1-3 | NIR to CNL translation bridge | Complete | — |
| 1 | T1-4 | Public `compile_to_nir()` surface | Complete | — |
| 2 | T2-x | Quantization, hybrid tags, partitioning | Later | Tier 1 stability |

---

## Non-Negotiable Constraints

1. **NIR fails closed.** Unsupported concepts must be rejected with structured diagnostics, never exported dishonestly.
2. **One canonical graph model.** Editor, canvas, and export cannot keep diverging local representations.
3. **Workspace state is product state.** Save/open behavior and cached NIR artifacts are part of the core experience, not optional polish.
4. **The public promise must match the product.** If active support is `CNL -> NIR`, docs and task order must stop implying runtime execution, training, or hardware deployment are first-class deliverables.
