# NMTK Master Task Order

## Active Scope: `CNL -> IR -> NIR` plus simulator E2E and critical NeuroSim/NeuroChip truthfulness

> **Plan maintenance**: this plan needs to be updated after each meaningful task change.
> **Update style**: keep the work-done note very short and concise.
> **Updated**: 2026-05-25
> **Latest concise update**: Added two new task specs. **T-BUNDLE** (`docs/current tasks/2026-05-24-nir-bundle-architecture.md`): architecture and implementation plan for the `.nmtk` project bundle format (NIR + learning rules + `internal_ir.json`), covering canvas gaps, NIR framework online-learning constraints (Lava-only), Phase 0 adapter–canvas disconnect fix, and a Lava `online_learn` adapter path. **T-LAYER** (`docs/current tasks/2026-05-24-layer-editor-view.md`): spec for a sequential row/column layer editor view in Studio (PyTorch-style `nn.Sequential` UX), where each layer card maps to one or two CNL sentences, layers can be grouped/expanded, and the view complements (does not replace) the graph canvas. T-LAYER is gated on T1-8 and T1-10.
>
> **Scope decision**: Active product support is centered on authoring, validating, exporting, and simulator-running `CNL -> IR -> NIR`, with two simulator targets in scope: Lava simulator and snnTorch simulator. Hardware deployment remains out of scope except for NeuroChip backend truthfulness needed by the CNL Studio deployment flow.
>
> **Sources merged** (originals archived to `docs/archive/`):
>
> - `docs/current tasks/neurocnl_status_and_priorities.md` → archived
> - `docs/unified_toolkit_architecture.md`
> - `docs/current tasks/2026-05-10-neurocnl-workspace-simulation-persistence-plan.md` → archived
> - `docs/current tasks/2026-05-13-quick-wins-and-bugfixes.md` → archived
> - `docs/current tasks/2026-05-13-cnl-matrix-and-phase-2-plan.md` → archived
> - `docs/current tasks/2026-05-13-clean-bidirectional-cnl-canvas-plan.md` → archived
> - `neurocnl/docs/CODE_REVIEW_CRITICAL_2026-05-14.md`
> - `Neurosim/CODE_REVIEW_2026-05-14.md`
> - `Neurochip/docs/CODE_REVIEW_CRITICAL_2026-05-14.md`
> - `docs/current tasks/2026-05-14-cnl-nir-simulator-contract-plan.md` → archived
> - `docs/current tasks/2026-05-14-lava-simulator-e2e-plan.md` → archived
> - `docs/current tasks/2026-05-14-snntorch-simulator-e2e-plan.md` → archived
> - `docs/current tasks/2026-05-16-neurochip-impl-tasks.md` → archived (T1-NC done)
> - `docs/current tasks/2026-05-16-neurochip-next-steps.md` → archived (T1-NC done; T2-x tracked below)
> - `docs/current tasks/weight_init_option_b_handoff.md` → archived (spec fully done)
> - `docs/current tasks/neurotraining_handoff.md` → archived (infrastructure implemented)
> - `docs/current tasks/nengo_fpga_and_spa_plan.md` → archived (Nengo-era, superseded by NIR-native)

---

## Scope Rules

- Keep in the active queue: CNL authoring, validation, workspace/file flows, NIR lowering, NIR export, NIR-backed graph/editor coherence, a backend-neutral simulator contract for Lava and snnTorch, critical NeuroSim fixes that prevent canvas/CNL/simulation workflows from lying about semantics, and critical NeuroChip fixes that prevent the CNL Studio deployment flow from lying about hardware readiness.
- Remove from the active queue: legacy execution backends outside the NIR simulator contract, training UI, benchmark-first APIs, broad hardware expansion, launcher/runtime feature work except optional simulator-worker wiring, and release-readiness tracking for non-NIR targets.
- Exception: NeuroSim P0/P1 stabilization is active because CNL Studio imports and mounts the `neurosim` package for canvas, preview, sweep, export, and project routes. Duplicate package resolution and semantic drift can make suite-visible behavior differ from module-local tests.
- Exception: NeuroChip P0/P1 stabilization is active because the frontend is integrated into CNL Studio and depends on NeuroChip backend truthfulness for deployment, diagnostics, and target support semantics.
- Historical docs for those broader workflows may remain in the repo, but they are not part of the current delivery order.

---

## Current Status (as of 2026-05-22)

- Confirmed complete: direct `CNL -> IR -> NIR` export exists for the currently supported subset.
- Confirmed complete: NIR export still fails closed for unsupported concepts instead of exporting dishonestly.
- Confirmed complete: actionable validation/export diagnostics are already normalized enough to support UI cleanup work.
- Confirmed complete: Lava and snnTorch simulator E2E (T1-5, T1-6, T1-7).
- Confirmed complete: NIR-native CNL compiler (`nir-native-cnl` spec — production code done; optional PBT tasks remain unchecked).
- Confirmed complete: weight-init Option B (`weight-init-option-b` spec — all tasks done).
- Confirmed complete: NIR editor sync bugs (`nir-cnl-editor-bugs`, `nir-editor-sync`, `nir-simulator-support-matrix`, `nir-target-aware-preflight` specs — all fully done).
- **Active gaps** are now concentrated in six areas:
  1. **`nir-cnl-editor-sync`** — NIR-native CNL does not round-trip through the Studio canvas editor yet (spec defined, no tasks started)
  2. **`studio-target-first-workflow`** — TargetChip / TargetPopover / deploy-target first-class placement not built (spec defined, no tasks started)
  3. **Sentence picker / autocomplete alignment** — `cnl_sentence_builder_dialog.dart` and `cnl_editor.dart` still emit forbidden legacy biological grammar that the new NIR-native parser rejects (see `docs/current tasks/2026-05-22-neurocnl-sentence-picker-nir-alignment.md`)
  4. **T0-A** — Workspace file I/O and NIR artifact persistence (native open/save, `.neurocnl-workspace.json` round-trip) not yet started
  5. **T0-C item 1** — workspace load performance profiling evidence still outstanding
  6. **`neurotraining-extensions`** and **`neurohub-global-registry`** specs — fully defined, zero tasks started
  7. **T-UI Flutter UI migration** — `shadcn_ui` → `zeta_flutter ^1.4.5` across all 6 Flutter packages; partial moon_design revert required first (see `docs/current tasks/2026-05-24-shadcn-to-zeta-flutter-migration.md`)
  8. **T-DEBT tech debt cleanup** — ✅ Tasks 1–4 done (stale worktree removed, Nengo surface deleted, all 5 app roots on `NmtkZetaTheme.wrap`, loading_screen button). 🔄 Tasks 5–8 deferred: 138 `ElevatedButton`/`TextButton`/`OutlinedButton` hits remain across 5 frontends — follow-on session. See `docs/current tasks/2026-05-24-tech-debt-cleanup-material-deprecated.md`

---

## Tier 0 — Immediate Work

### T0-CR: NeuroCNL Contract Stabilization From Critical Review

**Status**: Complete on 2026-05-14.
**Why first**: The 2026-05-14 review found product-contract failures that can make valid-looking workflows fail later. This must land before new NIR feature expansion, because validation, generation, docs, capability claims, and tests currently disagree about what NeuroCNL supports.

**Primary review doc**: `neurocnl/docs/CODE_REVIEW_CRITICAL_2026-05-14.md`

| Phase | Task                                                                                                                                                                                     | Priority | Key files                                                                                                                                                               |
| ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | Make `/api/validate` prove parse + IR lowering + NIR materialization readiness for NIR-backed workflows; return structured failures instead of green validation for impossible specs   | P0       | `backend/app/services/neurocnl_bridge.py`, `backend/app/routers/validate.py`, `neurocnl/pipeline.py`                                                              |
| 2     | Make `/api/generate` catch `LoweringError` and `MaterializerError`, returning structured 422 diagnostics instead of unhandled crashes                                              | P0       | `backend/app/routers/generate.py`, backend generate tests                                                                                                             |
| 3     | Make canonical CNL emission parser-compatible for every visible generated sentence, including inhibitory and STDP connection forms                                                       | P0       | `neurocnl/cnl/document.py`, `neurocnl/cnl/cnl_parser.py`, `backend/tests/test_generate_router.py`                                                                 |
| 4     | Resolve the NIR-only vs legacy-Nengo public contract across support matrix, capability registry, Python exports, REST export behavior, and tests                                         | P1       | `docs/support_matrix.md`, `neurocnl/__init__.py`, `neurocnl/backends/capabilities.py`, `backend/app/routers/export.py`, `backend/tests/test_export_router.py` |
| 5     | Sync stale regression tests with the intended normalized identifier contract and NIR-only REST behavior                                                                                  | P1       | `neurocnl/ir/test_ir_lowering.py`, `neurocnl/ir/test_materializer.py`, `neurocnl/cnl/test_cnl_parser.py`, backend tests                                           |
| 6     | Align Akida1 topology semantics without re-prioritizing hardware deployment; either mark sequential Akida1 unsupported everywhere or document/test the exact supported subset            | P1       | `neurocnl/backends/capabilities.py`, `neurocnl/planner.py`, `neurocnl/test_planner.py`, `docs/support_matrix.md`                                                |
| 7     | Collapse or rename the older `neurocnl.pipeline.compile_to_nir()` helper so backend code does not depend on a different API contract than public `neurocnl.compile.compile_to_nir()` | P1       | `neurocnl/pipeline.py`, `neurocnl/compile.py`, `backend/app/routers/export.py`                                                                                    |
| 8     | Harden report provenance and production exposure defaults after the P0/P1 contract work is green                                                                                         | P2       | `backend/app/routers/export.py`, `backend/app/main.py`, `backend/app/middleware/auth.py`                                                                          |

**Exit criteria**:

1. `/api/validate` and `/api/generate` agree on invalid specs and return structured diagnostics.
2. Generated CNL from `/api/generate` can be parsed and compiled through the supported NeuroCNL path.
3. Support matrix, capability registry, public Python exports, REST endpoints, and tests all describe the same NIR-only support boundary.
4. Focused gates pass: backend generate/validate/export tests, CNL parser tests, IR lowering/materializer tests, planner/capability tests, and `ruff`.

---

### T0-NS: NeuroSim Canvas, Simulation, and Package Truthfulness From Code Review

**Status**: Complete on 2026-05-14.
**Why second**: CNL Studio mounts NeuroSim routes for the suite-visible canvas, preview, sweep, export, and project flows. The 2026-05-14 NeuroSim review found a duplicate-package/import ambiguity plus semantic bugs that can make the canvas, generated CNL, preview output, sweep results, and hardware-oriented status claims disagree. This must land after the NeuroCNL contract fixes and before hardware deployment confidence work, because Studio cannot truthfully deploy a graph whose canvas semantics are already ambiguous.

**Primary review and implementation plan**: `Neurosim/CODE_REVIEW_2026-05-14.md`

| Phase | Task                                                                                                                                                                                                                          | Priority | Key files                                                                                                                                                                 |
| ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | Resolve `neurosim` package ownership and import ambiguity; choose one suite-mounted source of truth, migrate missing canonical/editor changes, and add an import-path guard that reports the resolved package path          | P0       | `Neurosim/neurosim/**`, `neurocnl/neurosim/**`, `neurocnl/backend/app/main.py`, `suite_api/domains/neurosim/router.py`, packaging/CI docs                         |
| 2     | Harden canonical NeuroSim graph semantics so NeuroCNL-backed paths accept only exactly one sensory -> motor static LIF edge and reject reversed direction, wrong roles, unsupported components, and unsupported synapse types | P0       | `neurosim/app/services/neurocnl_bridge.py`, `neurosim/app/services/semantic_cnl.py`, `neurosim/app/services/graph_to_cnl.py`, canonical generation/validation tests |
| 3     | Fix preview fidelity claims for `delay` and `threshold`: either implement true semantics or explicitly mark local preview/export approximate/unsupported with user-visible support metadata                               | P0       | `neurosim/app/services/preview_runner.py`, `neurosim/app/services/neurocnl_bridge.py`, `neurosim/components/synapses/static_synapse.json`, preview/export tests     |
| 4     | Make sweep parameter paths strict: malformed paths, missing ids, non-numeric parameters, and unsupported parameters must fail before any simulation result is accepted                                                        | P0       | `neurosim/app/services/sweep_runner.py`, `neurosim/contracts/design_contracts.py`, `neurosim/app/routers/sweep.py`, sweep service/router tests                      |
| 5     | Stop returning mock SpiNNaker2 zero data as completed; missing SDK/hardware must return failed or degraded capability metadata unless an explicit test/mock mode is enabled                                                   | P1       | `neurosim/app/backends/spinnaker2_backend.py`, `neurosim/app/routers/spinnaker2.py`, SpiNNaker2 tests, support/capability docs                                        |
| 6     | Repair verification reproducibility: make clean `uv`/documented pytest work without resolving unavailable hardware extras, fix pre-commit config paths, and align Python-version constraints                                | P1       | `Neurosim/pyproject.toml`, `Neurosim/.pre-commit-config.yaml`, test docs/CI config                                                                                    |
| 7     | Sanitize and escape export serializers so Python, SVG, NeuroML, and NIR exports cannot emit invalid or injected identifiers/text                                                                                              | P1       | `neurosim/app/routers/export.py`, export tests                                                                                                                          |
| 8     | Make runtime lifecycle truth explicit: document or replace in-memory jobs, improve WebSocket cancellation/error logging, and make project-store path/scope explicit                                                           | P2       | `neurosim/app/services/job_store.py`, `neurosim/app/routers/simulation_ws.py`, `neurosim/app/services/project_store.py`, project/runtime docs                       |
| 9     | Reconcile stale standalone frontend/spec/component promises with the current Studio-integrated product shape and remove or fill placeholder components/templates                                                              | P2       | `Neurosim/README.md`, `Neurosim/Makefile`, `Neurosim/neurosim_spec.md`, component/template manifests                                                                |

**Exit criteria**:

1. From repo root, `neurocnl/`, and `Neurosim/`, the intended suite-mounted `neurosim` package is unambiguous and covered by tests or startup diagnostics.
2. Canonical NeuroSim graph validation, CNL generation, preview support, and export support all reject motor -> sensory graphs instead of rewriting them as sensory -> motor.
3. `threshold` and `delay` are either simulated faithfully or downgraded with explicit support metadata; tests prove the chosen behavior.
4. Invalid sweep paths cannot produce completed sweep results.
5. SpiNNaker2 missing SDK/hardware cannot produce a completed all-zero result unless an explicit mock mode is requested and visible in the response.
6. Clean documented verification is reproducible: NeuroSim backend tests, `mypy`, `ruff`, and the suite-mounted NeuroSim route tests pass without hidden Anaconda-only assumptions.
7. NeuroSim docs say plainly that broad visual SNN simulation is not active support unless and until the implementation actually supports it.

---

### T0-NC: NeuroChip Deployment Truthfulness and Backend Stabilization From Critical Review

**Status**: Complete on 2026-05-14.
**Why third**: CNL Studio owns the deployment UI, but NeuroChip owns the backend/hardware layer behind that flow. The 2026-05-14 NeuroChip review found startup, verification, PYNQ artifact, analyzer, deploy-state, and documentation issues that can make CNL Studio show deployment confidence before the backend can prove it. This remains critical, but it follows NeuroSim truthfulness because deployment confidence depends on the canvas graph meaning being stable first.

**Primary review and implementation plan**: `Neurochip/docs/CODE_REVIEW_CRITICAL_2026-05-14.md`

| Phase | Task                                                                                                                                                                      | Priority | Key files                                                                                                                                                                                                     |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | Restore base backend import/startup with all optional SDKs absent; fix Lava/NumPy optional import behavior and app-level router loading                                   | P0       | `Neurochip/neurochip/app/main.py`, `Neurochip/neurochip/app/services/lava_backend.py`, `Neurochip/neurochip/app/routers/lava.py`, `Neurochip/pyproject.toml`                                          |
| 2     | Make NeuroChip verification green: documented pytest command, focused contract tests,`ruff`, and `mypy`                                                               | P0       | `Neurochip/pyproject.toml`, `Neurochip/neurochip/tests/**`, Lava router/backend typing                                                                                                                    |
| 3     | Make PYNQ export fail closed by validating generated artifacts and rejecting declared/generated topology drift before returning ZIPs                                      | P0       | `Neurochip/neurochip/app/routers/export.py`, `Neurochip/neurochip/app/services/pynq_generator.py`, `Neurochip/neurochip/contracts/pynq_runtime_artifact_contract.py`, PYNQ artifact tests               |
| 4     | Add target-specific analyzer/profile limits so PYNQ synapse capacity, population limits, overlay metadata, and capability levels are represented honestly                 | P1       | `Neurochip/neurochip/contracts/hardware_contracts.py`, `Neurochip/neurochip/targets/*.json`, `Neurochip/neurochip/app/services/constraint_analyzer.py`, target/router tests                             |
| 5     | Make hardware deploy responses explicit about simulator vs hardware and add a fail-closed hardware-required path for launcher/CNL Studio flows                            | P1       | `Neurochip/neurochip/app/routers/pynq.py`, `Neurochip/neurochip/app/services/pynq_backend.py`, `nmtk_ui_core/lib/models/pynq_deployment_model.dart`, CNL Studio deploy provider/surface                 |
| 6     | Improve PYNQ HTTP error taxonomy so missing board, probe timeout, register-map mismatch, and MMIO overflow surface distinct status codes and remediation hints            | P1       | `Neurochip/neurochip/app/routers/pynq.py`, `Neurochip/neurochip/app/services/pynq_backend.py`, `Neurochip/neurochip/app/services/pynq_worker.py`, `nmtk_ui_core` PYNQ models                          |
| 7     | Reconcile NeuroChip docs with CNL Studio-integrated frontend ownership and replace stale standalone frontend checks                                                       | P1       | `Neurochip/AGENTS.md`, `Neurochip/README.md`, `Neurochip/neurochip_spec.md`, related ADR/spec references                                                                                                |
| 8     | Harden mutating hardware surfaces: auth/CORS defaults, Akida remote dispatch allowlisting, flash job bounds, ZIP validation, deployment DB location, target ID resolution | P2       | `Neurochip/neurochip/app/auth.py`, `Neurochip/neurochip/app/main.py`, `Neurochip/neurochip/app/routers/akida.py`, `flash_service.py`, `pynq_compiler.py`, `deployment_store.py`, `quantizer.py` |
| 9     | Label heuristic quantization/fault/power/partition outputs with support levels and keep estimates out of deploy-readiness gates                                           | P2       | `quantizer.py`, `fault_runner.py`, `power_estimator.py`, `partitioner.py`, analysis/quantization/fault/estimation routers                                                                             |

**Exit criteria**:

1. `import neurochip.app.main` succeeds with PYNQ, Akida, Lava, Speck, and NumPy absent unless a feature explicitly requires NumPy.
2. `cd Neurochip && rtk poetry run pytest neurochip/tests -q`, `rtk poetry run ruff check .`, and `rtk poetry run mypy .` are green or the documented verification command is intentionally changed and green.
3. PYNQ export cannot return an artifact that `validate_pynq_compile_artifact()` rejects.
4. PYNQ analyzer, export, handoff, launcher/CNL Studio UI, and deploy responses agree on the 15,360-synapse overlay-v1.0.1 limit and simulator/hardware status.
5. CNL Studio deployment UI consumes explicit NeuroChip support levels and cannot mistake scaffold, simulator, SDK simulator, and real hardware deployment.
6. NeuroChip docs no longer describe a standalone frontend as the active owner; they point to the CNL Studio UI and keep NeuroChip focused on backend/hardware contracts.

---

### T0-A: Workspace File I/O and NIR Artifact Persistence

**Status**: Active.
**Why first**: Reliable save/open behavior is foundational, and cached NIR artifacts should stay attached to the file that produced them.

| Phase | Task                                                                     | Key files                                                    |
| ----- | ------------------------------------------------------------------------ | ------------------------------------------------------------ |
| 1     | Implement real native `open` / `save as` for `.cnl` files          | `platform_helper*.dart`, `import_text_file_picker*.dart` |
| 2     | Introduce `.neurocnl-workspace.json` round-trip support                | `workspace_file.dart`, `workspace_provider.dart`         |
| 3     | Scope cached NIR export results per file and restore them on file switch | `pipeline_provider.dart`, workspace model                  |
| 4     | Add rename + comparison panel in Studio UI                               | `studio_screen.dart`                                       |

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

**Status**: Active / Partially complete. Items 2–5 done. Item 1 profiling evidence still outstanding.
**Why now**: These are the highest-signal usability issues still relevant to a `CNL -> NIR` product.

1. **Workspace Load Performance**: profile the load path and add the "Obsidian Flow" loading treatment when delay is structural. *(loader + overlay exist, profiling evidence not yet captured — still active)*
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

**Status**: Complete on 2026-05-14.
**Supported subset**:

1. `short_term_plasticity` — depression with numeric utilization lowers approximately by scaling NIR `Linear` weights; facilitation and incomplete rules remain metadata-only.
2. `lateral_inhibition` — lowers approximately to dense inhibitory masks, with warnings when shape-aware locality is degraded.
3. `homeostatic_plasticity` — numeric target rates lower approximately by adjusting LIF threshold; incomplete rules remain metadata-only.
4. `neuromodulation` — preserved as validated structured metadata; no executable NIR modulatory operator is claimed.

Unsupported semantic subcases remain fail-closed or explicitly metadata-only, and tests cover the supported verdicts.

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

---

### T1-5: Shared `CNL -> NIR -> Simulator` Contract

**Status**: Complete on 2026-05-15.
**Why now**: Lava and snnTorch simulator work needs one product contract so the Studio does not grow two incompatible runtime paths. This task is the prerequisite for simulator-specific implementation.

**Primary plan doc**: `docs/current tasks/2026-05-14-cnl-nir-simulator-contract-plan.md`

1. Define backend-neutral simulator capability, request, result, and diagnostic schemas.
2. Add NIR runtime support classification for `lava_sim` and `snntorch_sim`.
3. Add deterministic stimulus helpers for explicit and generated spike trains.
4. Add `GET /api/simulators/capabilities` and `POST /api/simulators/run`.
5. Add a Studio simulation panel after NIR generation.

**Exit criteria**:

1. A user can create CNL, generate NIR, select a simulator backend, and see capability/preflight status before running.
2. Unsupported NIR semantics fail before runtime dispatch with structured diagnostics.
3. Lava and snnTorch simulator results share one response shape.
4. Missing optional dependencies never break base NeuroCNL startup.

---

### T1-6: Lava Simulator E2E

**Status**: Complete on 2026-05-15.
**Why now**: Lava already has NeuroCNL conversion and NeuroChip runtime pieces, but it is not yet a first-class simulator path from CNL Studio.

**Primary plan doc**: `docs/current tasks/2026-05-14-lava-simulator-e2e-plan.md`

1. Add a Lava simulator adapter behind the shared simulator contract.
2. Convert compiled NIR to Lava runtime payloads via `LavaIO`.
3. Dispatch to an in-process compatible runtime or optional isolated Lava worker.
4. Keep Loihi hardware out of the default flow; use simulator mode only.
5. Normalize Lava spike output into the shared simulator result schema.

**Exit criteria**:

1. A supported CNL model can compile to NIR and run in Lava simulator mode.
2. Missing `lava-nc` returns actionable unavailable/preflight status.
3. Unsupported NIR nodes fail before Lava dispatch.
4. Studio labels Lava as a simulator backend, not hardware deployment.

---

### T1-7: snnTorch Simulator E2E

**Status**: Complete on 2026-05-15.
**Why now**: snnTorch has a training adapter scaffold, but the user-facing need is fixed-weight simulation of generated NIR before any training workflow.

**Primary plan doc**: `docs/current tasks/2026-05-14-snntorch-simulator-e2e-plan.md`

1. Add a snnTorch simulator adapter separate from the training adapter.
2. Validate and topologically order supported feed-forward NIR graphs.
3. Map `nir.Linear` and NIR LIF nodes to fixed-weight torch/snnTorch modules.
4. Run deterministic timestep simulation from the shared stimulus contract.
5. Normalize spikes and optional membrane traces into the shared simulator result schema.

**Exit criteria**:

1. A supported CNL model can compile to NIR and run in snnTorch simulator mode.
2. Missing `torch` or `snntorch` returns actionable unavailable/preflight status.
3. snnTorch simulation is clearly separate from training.
4. Exact CNL-authored weights are preserved in the snnTorch module.



### T1-X: API Provenance and Production-Safe Defaults

**Status**: Queued after T0-CR.
**Why after stabilization**: HTML report trust boundaries and exposed-backend defaults matter, but they should not interrupt the P0/P1 compiler-contract fixes unless the backend is being prepared for non-local deployment.

1. Recompute or explicitly label client-provided summaries in HTML report export.
2. Include generated-at, NeuroCNL version, validation status, and provenance metadata in report exports.
3. Preserve local-development convenience while making non-loopback production mode require explicit CORS origins and auth configuration.
4. Add tests for local defaults and production fail-closed behavior.

---

---

### T1-8: NIR-Native CNL Editor Round-Trip (nir-cnl-editor-sync)

**Status**: Active — spec defined, no tasks started.
**Why now**: NIR-native CNL authored in the editor does not round-trip through the Studio canvas. This breaks the core authoring → canvas → edit → re-validate loop for NIR-native specs.

**Kiro spec**: `.kiro/specs/nir-cnl-editor-sync/`

Two bugs to fix:
1. **Fix 1 (backend)**: `parse-cnl-canonical` routes NIR-native CNL to the biological path, returning an empty canvas instead of parsing via `NIR_CNL_Parser → NIR_Compiler → serialize_nir_to_canvas_graph`.
2. **Fix 2 (frontend)**: `CanvasNode` Dart model and `sync_provider.dart` hardcode `componentId = 'lif_population'` regardless of the node's actual NIR type.

**Exit criteria**:
1. NIR-native CNL sent to `parse-cnl-canonical` returns HTTP 200 with a populated canvas whose nodes carry correct `nir_type` and `componentId`.
2. Non-LIF NIR nodes (Input, Output, Conv2d, etc.) appear on the canvas with the correct type badge.
3. Biological CNL path is unchanged.

---

### T1-9: Studio Target-First Workflow (studio-target-first-workflow)

**Status**: Active — spec defined, no tasks started.
**Why now**: Deploy-target selection is buried in the deploy panel. Users should be able to see and change the active target from the main toolbar before they click Run.

**Kiro spec**: `.kiro/specs/studio-target-first-workflow/`

Key deliverables:
1. Extract `DeployTargetData` model and `kDeployTargets` to a shared file.
2. `TargetChip` widget in the `_PipelineWorkspaceHeader` toolbar showing the active target with a `CompatibilityDot` for simulator targets.
3. `TargetPopover` overlay opened by tapping the chip, listing all six targets.
4. `PipelineBar` Deploy step shows "Select a target" and opens the popover when no target is selected.
5. `_BackendSupportCard` subtitle enriched with the selected simulator target label.

**Exit criteria**: Tapping the TargetChip changes the active target across Studio, PipelineBar, and the deploy panel without navigating away.

---

### T1-10: Sentence Picker and Autocomplete NIR Alignment

**Status**: Active — gap identified 2026-05-22, no spec created yet.
**Why now**: The CNL Sentence Builder dialog and editor autocomplete still emit legacy biological grammar (MUST, sensory, motor, STDP, threshold_firing, refractory_period) that the NIR-native parser's denylist immediately rejects. Every sentence added via the picker is a parse error.

**Gap doc**: `docs/current tasks/2026-05-22-neurocnl-sentence-picker-nir-alignment.md`

Key files:
- `neurocnl/frontend/lib/widgets/cnl_sentence_builder_dialog.dart` — `_kConcepts` list
- `neurocnl/frontend/lib/widgets/cnl_editor.dart` — `_kAllTemplates` list

**Exit criteria**:
1. Every sentence inserted by the picker or autocomplete is valid NIR-native CNL that passes `NIR_CNL_Parser().parse()` without raising `ParseError`.
2. Picker categories map to NIR primitives: Input/Output ports, LIF, LI, Linear transformation, Connections.
3. Autocomplete suggestions are valid `Define ...` and `Connect ... to ...` forms.

---

### T2-EXT: Neurotraining Extensions (neurotraining-extensions)

**Status**: Spec defined, no tasks started. Lower priority than T1-8 through T1-10.

**Kiro spec**: `.kiro/specs/neurotraining-extensions/`

Key deliverables: `DatasetLoader`, `NorseAdapter`, `SpikingJellyAdapter`, `WeightInjector`, `POST /api/training/jobs/{job_id}/export-nir` endpoint, Flutter `TrainingInspectorPanel` dataset source toggle and Export NIR button.

---

### T2-HUB: Neurohub Global Registry (neurohub-global-registry)

**Status**: Spec defined, no tasks started. Out of active priority until T1-8 through T1-10 stabilize.

**Kiro spec**: `.kiro/specs/neurohub-global-registry/`

Key deliverables: Registry FastAPI backend (artefacts, search, auth, community, ratings), neurohub-CLI (`neurohub push/pull/search`), Flutter in-app discovery panel, Next.js public site.

---

### T-BUNDLE: NIR + Training Bundle Architecture

**Status**: Spec defined, no tasks started. Gated on T1-8 (canvas model must be correct first).
**Why**: Formalises the `.nmtk` ZIP bundle format (NIR + learning rules + `internal_ir.json`), fixes the adapter–canvas disconnect, and defines the Lava online-learning path as the only NIR-portable STDP route.

**Full spec**: `docs/current tasks/2026-05-24-nir-bundle-architecture.md`

| Phase | Deliverable | Key files |
|---|---|---|
| 0 | Fix adapter–canvas disconnect: adapters read user NIR graph from payload | `neurocnl/training/snntorch_adapter.py`, `training_inspector_panel.dart` |
| 1 | `NetworkIR.to_dict()` + `ProjectBundle` ZIP container | `neurocnl/ir/types.py`, new `neurocnl/bundle.py` |
| 2 | `LearningRuleProjection` on `CanvasEdge`; plastic edge visual style | `canonical_editor_document.dart`, `network_graph_view.dart` |
| 3 | `reward_signal` on `LearningRuleIR`; `deployment_mode` on `TrainingRequest` | `neurocnl/ir/types.py`, `training_registry.py` |
| 4 | `BindsNETAdapter` (simulation-only, no NIR export) | `neurocnl/training/bindsnet_adapter.py` |
| 4b | `LavaOnlineAdapter` — the only NIR-portable `online_learn` path | `neurocnl/training/lava_online_adapter.py`, `lava_exporter.py` |
| 5 | Studio works against `ProjectBundle`; reward node in palette | `studio_screen.dart`, `nmtk_ui_core` |

**Critical constraint**: `deployment_mode = "online_learn"` is **Lava → Loihi 2 only**. BindsNET and SpikingJelly have no NIR bridge.

---

### T-LAYER: Sequential Layer Editor View

**Status**: Spec defined, no tasks started. **Gated on T1-8 and T1-10**.
**Why**: Adds a `nn.Sequential`-style layer list view to Studio. Each layer card = one or two CNL sentences. Layers group/expand to reveal parameters and learning rules. Rows = feedforward depth; columns = parallel pathways. Complements the graph canvas — does not replace it.

**Full spec**: `docs/current tasks/2026-05-24-layer-editor-view.md`

| Phase | Deliverable |
|---|---|
| 1 | `CanvasProjection` gains `orientation` + `groups`; `CanvasNotifier` gets `addLayer`/`reorderLayer` |
| 2 | `LayerCard` + `LayerEditorShell` widgets (display-only); Studio view-mode toggle (Graph ⇔ Layers) |
| 3 | Editable layer forms; drag-to-reorder; learning rule sub-section |
| 4 | Column orientation; groups; branch/merge nodes |
| 5 | Teaching mode: live CNL preview, grammar tooltips |

**Framework alignment**: snnTorch `Leaky`, Norse `LIFCell`, Lava `Dense+LIF`, PyTorch `nn.Sequential` all map to the same layer-card schema — the math is identical.

**Exit criteria**: Build a feedforward SNN in the layer editor, read the generated CNL, export valid NIR — without writing CNL manually.

---

### T0-NC-VERIFY: Confirm T0-NC Exit Criteria Are Actually Green

**Status**: Active.
**Why now**: T0-NC was marked complete on 2026-05-14 — the same day as the code review that identified the issues. Before building new Neurochip work on top, the exit criteria must be confirmed to hold in the current repo state.

**Primary task doc**: `docs/current tasks/2026-05-16-neurochip-next-steps.md`

Exit criteria to verify:

1. `cd Neurochip && poetry run python -c "import neurochip.app.main"` succeeds with all optional SDKs absent.
2. `poetry run pytest neurochip/tests -q`, `poetry run ruff check .`, and `poetry run mypy .` are all green.
3. PYNQ export cannot return a ZIP that `validate_pynq_compile_artifact()` rejects.
4. PYNQ analyzer, export, handoff, and CNL Studio UI all agree on the 15,360-synapse overlay-v1.0.1 limit.
5. CNL Studio deployment UI cannot mistake simulator for real PYNQ hardware deployment.
6. NeuroChip docs no longer describe a standalone frontend as the active owner.

---

### T1-NC: Neurochip Next Phase — Provenance, Partition Wiring, Hardening

**Status**: Active (starts after T0-NC-VERIFY passes).
**Why now**: T1-x (API provenance) is unblocked since T0-CR completed. Neurochip's hardware control routes need auth/CORS hardening. The `/partition` endpoint has a real implementation that just needs wiring.

**Primary task doc**: `docs/current tasks/2026-05-16-neurochip-next-steps.md`

| Phase | Task | Priority | Key files | Status |
|-------|------|----------|-----------|--------|
| 1 | Fail startup when auth is enabled with default key; narrow CORS to loopback by default | P1 | `Neurochip/neurochip/app/auth.py`, `app/main.py` | ✅ Done 2026-05-16 |
| 2 | Add Akida `remote_server` allowlist; block private/loopback/metadata targets by default | P1 | `Neurochip/neurochip/app/routers/akida.py` | ✅ Done 2026-05-16 |
| 3 | Add `generated_at`, `neurochip_version`, `validation_status` provenance to export/deploy responses | P1 | `Neurochip/neurochip/app/utils/provenance.py` (new), affected routers | ✅ Done 2026-05-16 |
| 4 | Wire `/api/neurochip/analysis/partition` to `suggest_partitions()` | P1 | `Neurochip/neurochip/app/routers/analysis.py`, `services/partitioner.py` | ✅ Done 2026-05-16 |
| 5 | Mount or explicitly deprecate `spinnaker2.py` router in `main.py` | P2 | `Neurochip/neurochip/app/main.py`, `routers/spinnaker2.py` | ✅ Done 2026-05-16 (mounted) |

**Exit criteria**:

1. ✅ `NEUROCHIP_AUTH_ENABLED=true` with default key refuses to start.
2. ✅ Akida remote dispatch cannot POST to loopback/private/metadata targets.
3. ✅ Export responses carry provenance fields.
4. ✅ `/partition` returns a real `PartitionResult`, not a placeholder 501.
5. ✅ SpiNNaker 2 router is mounted and available at `/api/neurochip/hardware/spinnaker2`.

**Implementation docs**: `docs/current tasks/2026-05-16-neurochip-impl-tasks.md`

**Verification result (2026-05-16)**:
- `ruff check .` — clean (0 errors)
- `pytest neurochip/tests/ -q` — 382 passed, 1 pre-existing failure in `test_targets_router.py::test_list_targets_skips_malformed_file` (not introduced by this work; confirmed by git stash check)
- `mypy` — 1 pre-existing error in `lava_backend.py` (not introduced by this work)

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

| Task                                                               | Reason                                                                                                                                  |
| ------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| Legacy execution-backend work outside the new simulator contract   | Outside the active `CNL -> NIR -> simulator` support boundary                                                                         |
| Runtime-specific feature work outside Lava/snnTorch NIR simulators | Outside the active simulator support boundary                                                                                           |
| Training UI and training framework adapters                        | Outside the active simulator support boundary; snnTorch fixed-weight simulation is in scope, training is not                            |
| Broad hardware deployment expansion and release-readiness work     | Outside the active `CNL -> NIR` support boundary; exception is T0-NC stabilization needed for the existing CNL Studio deployment flow |
| Benchmark-first APIs                                               | Outside the active `CNL -> NIR` support boundary                                                                                      |
| LLM-assisted CNL                                                   | Still too early                                                                                                                         |
| WASM browser runtime                                               | Still not viable for the workload                                                                                                       |

---

## Execution Summary

| Tier | ID    | Task                                                                             | Status   | Blocked by       |
| ---- | ----- | -------------------------------------------------------------------------------- | -------- | ---------------- |
| 0    | T0-CR | NeuroCNL contract stabilization from critical review                             | Complete | —               |
| 0    | T0-NS | NeuroSim canvas, simulation, and package truthfulness from code review           | Complete | —               |
| 0    | T0-NC | NeuroChip deployment truthfulness and backend stabilization from critical review | Complete | —               |
| 0    | T0-NC-VERIFY | Confirm T0-NC exit criteria are green in current repo state               | Active   | —               |
| 0    | T0-A  | Workspace file I/O and NIR artifact persistence                                  | Active   | —               |
| 0    | T0-B  | Actionable error diagnostics                                                     | Complete | —               |
| 0    | T0-C  | Quick wins and bugfixes (item 1 profiling outstanding)                           | Active   | —               |
| 0    | T0-D  | STP NIR type mismatch and round-trip fix                                         | Complete | —               |
| 0    | T0-E  | Matrix-native CNL on top of IR                                                   | Complete | —               |
| 1    | T1-1  | NIR semantic coverage expansion                                                  | Complete | —               |
| 1    | T1-2  | NIR as canonical Studio graph model                                              | Complete | —               |
| 1    | T1-3  | NIR to CNL translation bridge                                                    | Complete | —               |
| 1    | T1-4  | Public `compile_to_nir()` surface                                              | Complete | —               |
| 0    | T1-NC | Neurochip next phase: provenance, partition wiring, hardening                    | Complete | 2026-05-16       |
| 1    | T1-x  | API provenance and production-safe defaults                                      | Queued   | T0-CR            |
| 1    | T1-5  | Shared `CNL -> NIR -> Simulator` contract                                      | Complete | 2026-05-15       |
| 1    | T1-6  | Lava simulator E2E                                                               | Complete | 2026-05-15       |
| 1    | T1-7  | snnTorch simulator E2E                                                           | Complete | 2026-05-15       |
| 1    | T1-8  | NIR-native CNL editor round-trip (`nir-cnl-editor-sync`)                       | Active   | —               |
| 1    | T1-9  | Studio target-first workflow (`studio-target-first-workflow`)                    | Active   | —               |
| 1    | T1-10 | Sentence picker and autocomplete NIR alignment                                   | Active   | —               |
| 2    | T2-EXT | Neurotraining extensions                                                        | Queued   | T1-8 stable      |
| 2    | T2-HUB | Neurohub global registry                                                        | Queued   | T1-8 stable      |
| 2    | T-BUNDLE | NIR + training bundle architecture (`.nmtk` format, adapter–canvas fix)    | Queued   | T1-8             |
| 2    | T-LAYER  | Sequential layer editor view (row/column, group/expand, CNL preview)         | Queued   | T1-8 + T1-10     |
| 2    | T2-x  | Quantization, hybrid tags, partitioning                                          | Later    | Tier 1 stability |

---

## Non-Negotiable Constraints

1. **NIR fails closed.** Unsupported concepts must be rejected with structured diagnostics, never exported dishonestly.
2. **One canonical graph model.** Editor, canvas, and export cannot keep diverging local representations.
3. **Workspace state is product state.** Save/open behavior and cached NIR artifacts are part of the core experience, not optional polish.
4. **The public promise must match the product.** Active runtime support is limited to `CNL -> NIR -> Lava/snnTorch simulator` until proven otherwise; docs and task order must stop implying training or broad hardware expansion are first-class deliverables. The existing CNL Studio deployment flow must label NeuroChip scaffold, simulator, SDK simulator, and hardware states truthfully.
5. **Validation must prove lowerability.** A green validation result must mean the spec can pass the supported parse, IR-lowering, and NIR-materialization path.
6. **Generated CNL must be parser-owned.** NeuroCNL must never emit visible canonical CNL that its own parser rejects.
7. **Canvas meaning must be stable.** NeuroSim must never silently rewrite a canvas graph into a different canonical CNL graph, and the suite must import one unambiguous `neurosim` package.
8. **Simulation support levels must be explicit.** NeuroSim must label approximate, local-only, mock, degraded, and unsupported preview/export/hardware paths instead of returning completed-looking results for behavior it did not faithfully simulate.
9. **Hardware readiness must be explicit.** NeuroChip must never return or surface deployment success without saying whether the path used scaffold generation, simulation, SDK simulator mapping, or real hardware.

---

## T-UI: Flutter UI — shadcn_ui → zeta_flutter Migration

**Status**: ✅ Complete (2026-05-24).
**Full plan**: `docs/current tasks/2026-05-24-shadcn-to-zeta-flutter-migration.md`
**Why now**: A partial moon_design migration left `nmtk_ui_core` in a broken mid-flight state. Switched to `zeta_flutter ^1.4.5` (Zebra Design System, MIT).

| Task | Description | Status |
|------|-------------|--------|
| T-UI-1 | Revert nmtk_ui_core to pre-moon shadcn baseline | ✅ |
| T-UI-2 | Add `zeta_flutter: ^1.4.5` to nmtk_ui_core; create `NmtkZetaTheme` | ✅ |
| T-UI-3 | Replace all Shadcn components in `nmtk_ui_core/lib/` with Zeta | ✅ |
| T-UI-4 | Delete `shad_theme.dart`; remove `shadcn_ui` from nmtk_ui_core pubspec | ✅ |
| T-UI-5 | Migrate `neurocnl/frontend` | ✅ |
| T-UI-6 | Migrate `Neurobench/frontend` | ✅ |
| T-UI-7 | Migrate `nmtk/neuro_toolkit` | ✅ |
| T-UI-8 | Migrate `Neurohub/frontend` + `Neurosense/frontend` | ✅ |
| T-UI-9 | Full suite verification — zero `shadcn_ui` references | ✅ |

**Exit criteria met**: `grep -r "shadcn_ui" --include="*.dart" --include="*.yaml" . --exclude-dir=.claude` returns nothing; all 6 Flutter packages pass `flutter analyze` (0 errors each).

**Key implementation notes**:
- `ZetaButton` takes `label: String` + `leadingIcon: IconData?` (no Widget child)
- `ZetaTooltip` is a display widget, not a hover wrapper — used Material `Tooltip` instead
- `ZetaBadge` does not exist in 1.4.5 — used `Container` pill instead
- `ZetaCustomTheme` is not const-constructible
- `ShadCard` props (`padding`, `border`, `radius`) → converted to `Container(decoration: BoxDecoration(...))`
- Complex `leading: Widget` buttons (loading spinners) → converted to `ElevatedButton` with `Row` child
