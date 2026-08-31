# Play: Finishing Stages 5 and 6 of the Python Major Refactor

## Context

[`python-major-refactor-plan.md`](../2026-08-25/python-major-refactor-plan.md) is ~53% complete.
Stages 1–4 are done. Stage 5 (NeuroCNL notebook generation) is underway — the graph-analysis
boundary (`backend/app/services/notebook_graph_analysis.py`) is extracted; everything else in
`neurocnl/backend/app/routers/notebook.py` (4,475 lines) is still tangled together. Stage 6
(NeuroCNL core) has not started.

**Scope decision from this planning session:** stage 6 was assumed to be a single compiler
pipeline (`nir_cnl/`). Research found a second, equally live pipeline: `neurocnl/cnl/` +
`neurocnl/ir/lowering.py` + `neurocnl/ir/materializer.py` back the canvas-editing sync routes
(`/api/neurosim/generation.py` → `canonical_editor_projection.py`) that the same CNL Studio canvas
(`canvas_screen.dart`) calls for parse-as-you-type and canvas↔CNL↔NIR sync. `nir_cnl/` handles
compile-time notebook generation; `cnl/ir` handles interactive canvas editing. Neither is dead.
The user chose to **broaden stage 6 to refactor both pipelines** in this program, while explicitly
**not** merging them into one — that consolidation is a separate, future, separately-approved
project.

This roughly doubles stage 6's original 11-point estimate for the core-only scope; call it
**~18–20 points** with the canvas-sync pipeline included, and stage 5's remaining work **~10–11
points** (1 point of the original 12 already spent on graph analysis). Total remaining for both
stages: **~28–31 of the program's ~47 remaining points** — the largest chunk left.

## Ground truth (what's actually there today)

**Stage 5 — `neurocnl/backend/app/routers/notebook.py`, still to extract:**
- `_dag_node_code` (1910–2551, ~641 lines): the "~600-line node dispatch" the plan names —
  an if/elif chain from training-DAG node type → code string. No fail-closed behavior for an
  unknown node type today.
- `_phase_dag_to_code` (2901–3057) + `_training_phase_to_code` (2620–2901) + small helpers
  (2551–2620): DAG-to-training-code lowering.
- Per-target generators: `_generate_snntorch_code` (456–1116, ~660 lines, by far the largest),
  `_generate_sc_neurocore_code` (1116–1210), `_generate_akida_code` (1210–1277),
  `_generate_rockpool_code` (1277–1331), `_akida_exporter_code` (1575–1692), `_akida_bundle_code`
  (1692–1750), `_custom_pipeline_node_code` (1529–1575), dispatched by `_generate_arch_code`
  (3350–3444).
- Notebook assembly: `_build_v2_notebook` (3501–3732), `_build_akida_mnist_notebook`
  (3771–3897), cell/markdown builders scattered at 152–401 and 3487.
- 12 route handlers (1394–4471) — none are transport-only yet; most delegate into the blocks above.

**Stage 6 — two pipelines:**
- `nir_cnl/` (compile-time, used by `compile_to_nir()`): `tokenizer.py` (82),
  `grammar_tables.py` (621), `parser.py` (1441), `errors.py` (107), `ir_types.py` (302),
  `compiler.py` (1421, the core materialization stage), `shape_inference.py` (170),
  `size_propagation.py` (170), `pipeline_config.py` (106), `validator.py` (302). Already
  reasonably decomposed — `compiler.py` and `parser.py` are the two remaining oversized files.
- `cnl/ir` (interactive canvas sync, used by `/api/neurosim/generation.py`):
  `cnl/document.py`, `cnl/types.py`, `ir/lowering.py` (990, parameter resolution/node factories),
  `ir/materializer.py` (1139, validation + lowering + metadata combined), `ir/timing_validator.py`
  (98), `ir/metadata_schema.py` (109).
- `planner.py` (1176 lines): single file for Teensy/PYNQ/Akida deployability classification,
  **no dedicated test file** — the biggest coverage gap in stage 6. Per-target contracts,
  exporters, mappers, and handoff logic already live in `contracts/`, `export/`, `mapping/`,
  `handoff/`.
- Existing characterization coverage: solid for `nir_cnl/` (round-trip, shape, weight-init,
  grammar, diagnostics tests) and for the canvas-sync path (`neurosim/tests/routers/
  test_generation.py`, `test_generation_canonical.py`, `neurosim/tests/services/
  test_canonical_editor_projection.py`). **Zero** direct tests target `planner.py`'s
  classification logic — only its contract-layer output.

## The play, in order

Each slice ends green (Ruff, format, mypy on the touched module, focused tests, full module
suite, Suite API + cross-module checks) before the next starts, per the program's own rule:
small independently-green changes, never a repository-wide rewrite.

### Stage 5 — finish notebook generation

1. **Node-emitter registry.** Extract `_dag_node_code` into a registry of typed node emitters
   (one class/function per training-DAG node type, keyed by type string). An unknown node type
   must raise a structured diagnostic, not silently fall through. This is the single highest-value
   move in stage 5 — it's a real correctness gap today, not just a tidiness issue.
2. **DAG lowering module.** Move `_phase_dag_to_code`, `_training_phase_to_code`, and the small
   phase-helpers into `notebook_dag_lowering.py`, built on the registry from step 1.
3. **Target emitters.** Split `_generate_snntorch_code`, `_generate_sc_neurocore_code`,
   `_generate_akida_code`, `_generate_rockpool_code`, `_akida_exporter_code`,
   `_akida_bundle_code`, and `_custom_pipeline_node_code` into a `notebook_targets/` package,
   each implementing one shared typed target interface; `_generate_arch_code` becomes the
   dispatcher over that interface instead of an if/elif chain.
4. **Notebook assembly module.** Move `_build_v2_notebook`, `_build_akida_mnist_notebook`, and
   the cell/markdown builders into `notebook_assembly.py`, consuming the DAG-lowering and
   target-emitter modules from steps 2–3.
5. **Thin the routes.** Reduce all 12 route handlers to request validation → one service call →
   response mapping. Drop compatibility re-exports that no internal consumer still imports
   (check via the same private-import grep used for the graph-analysis slice).
6. **Split the tests.** Break the oversized notebook test files apart by concern — contracts,
   DAG lowering, target emitters, assembly, artifacts/publishing, endpoint integration — mirroring
   the new module boundaries, with shared typed fixtures.

### Stage 6 — both compiler pipelines

7. **Planner characterization first.** Before touching `planner.py`, add direct unit tests for
   its Teensy/PYNQ/Akida classification logic (not just the contract-layer tests that exist today).
   This closes the biggest test-coverage gap in the whole remaining program.
8. **Split the planner.** Break `planner.py` into per-target planners (Teensy, PYNQ, Akida) over
   one shared immutable network-facts model, so neuron/synapse/memory limit checks aren't
   duplicated — using the existing `contracts/`, `export/`, `mapping/`, `handoff/` modules as the
   per-target owners the planners delegate to.
9. **`nir_cnl` compiler split.** Extract parameter resolution and node-factory construction out
   of `compiler.py` (1421 lines) into their own modules alongside the existing
   `shape_inference.py`/`size_propagation.py`, keeping `compile.py`'s public façade unchanged.
10. **`nir_cnl` parser split.** Separate cursor/diagnostic utilities from the sentence-level
    parsing logic in `parser.py` (1441 lines); `tokenizer.py` and `grammar_tables.py` are already
    separate and don't need to move.
11. **`ir/materializer.py` split.** Break its combined validation + lowering + metadata concerns
    into explicit stages (it already delegates timing/metadata validation to
    `timing_validator.py`/`metadata_schema.py` — this step is about the remaining logic inside
    `materializer.py` itself).
12. **`ir/lowering.py` split.** Separate parameter resolution from node-factory construction,
    mirroring the structure chosen for the `nir_cnl` compiler in step 9 so the two pipelines read
    consistently even though they stay separate.
13. **Golden fixtures across both pipelines.** Add/confirm parser-render round-trip properties,
    shape/limit boundary tests, and golden NIR fixtures for both `nir_cnl` and `cnl/ir` before and
    after each move — the plan requires this ahead of code movement, not after.
14. **Explicitly do not unify.** Confirm at the end of stage 6 that `nir_cnl` and `cnl/ir` remain
    two independently-owned pipelines. Consolidating them is a separate future decision requiring
    its own approval — not a byproduct of this refactor.

## The 80/20 inside this play

If only two slices happen, make them **#1 (node-emitter registry)** and **#7+#8 (planner
characterization + split)**. Both are the parts of stages 5–6 with the least existing safety net
and the most silent-failure risk today: an unsupported training-DAG node currently degrades
quietly instead of failing loudly, and `planner.py`'s hardware-deployability logic — the thing
that decides whether a network fits on a Teensy/PYNQ/Akida board — has no direct test coverage at
all. Everything else in this play (splitting already-working generators, already-covered parsers,
route thinning) is real but lower-risk: it's already exercised by existing tests, so a mistake
there is more likely to be caught immediately than to ship silently.

## Constraints carried over from the plan

- Preserve every route, response body, generated notebook byte, grammar pattern, and hardware
  handoff field. No approval exists to change any of those as a side effect of this work.
- Keep one-release compatibility re-exports for every moved private name; remove only after
  confirming (by grep, as done for graph analysis) that no internal consumer still imports it.
- Golden fixtures and characterization tests come *before* code moves in every slice, not after.
- `cnl/ir` is now confirmed live and in-scope, but it drives real-time canvas editing — treat its
  characterization tests as a harder gate than usual before moving anything, since a regression
  there is user-visible on every keystroke, not just on notebook generation.
