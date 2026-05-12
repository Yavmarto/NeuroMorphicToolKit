# NMTK Master Task Order
## Merging Market Intelligence Findings + `docs/` Implementation Plans

> **Created**: 2026-05-12  
> **Sources merged**:
> - `NMTK_SIDE/market_intelligence/02_strategic_findings.md` (market intelligence audit)  
> - `docs/neurocnl_status_and_priorities.md` (authoritative NeuroCNL source of truth)  
> - `docs/unified_toolkit_architecture.md` (v2.0, May 8 2026)  
> - `docs/AKIDA_RUNTIME_ACTIONS_PLAN.md` (May 7 2026)  
> - `docs/2026-05-10-neurocnl-workspace-simulation-persistence-plan.md`  
> - `docs/Release readiness/TEENSY_RELEASE_READINESS.md` — **COMPLETE**  
> - `docs/Release readiness/AKIDA_RELEASE_READINESS.md` — early usable  
> - `docs/Release readiness/PYNQ_RELEASE_READINESS.md`  
> - `docs/STATUS_SUMMARY_2026_05_10.md`

---

## Where the Plans Agree vs. Conflict

| Topic | Market Intel says | docs/ say | Verdict |
|-------|-------------------|-----------|---------|
| NIR as pivot format | ✅ Implemented (nir≥1.0.0, 8 converters) | ✅ "Direct CNL→IR→NIR export path present" | **Full agreement — confirmed done** |
| NIR coverage gaps | `lateral_inhibition`, `homeostasis`, etc. not lowered | "Some concepts lower only approximately or as metadata" | **Full agreement — broaden NIR lowering next** |
| Prophesee integration | ✅ Implemented (router + source + hardware worker) | ✅ "Updated support for Prophesee cameras" | **Full agreement — confirmed done** |
| Canvas ↔ CNL sync | ✅ Bidirectional sync implemented (studio_screen.dart) | ✅ "Improved synchronisation between text editor and visual canvas" | **Full agreement — WIP not missing** |
| Training adapter | Not in market intel scope | 🔴 "No concrete snnTorch / SpikingJelly adapters" — #1 priority in docs | **docs/ are more specific here — adopt docs/ order** |
| Actionable error diagnostics | Not called out in market intel | 🔴 "Make parse/validation failures consistently actionable" — #2 priority in docs | **docs/ are more specific — adopt docs/ order** |
| NeuroBench integration | 🔴 "Custom schema, upstream library not used" | 🟡 "NeuroBench-facing execution and metric-normalization groundwork" | **Market intel reveals the gap more precisely — upstream library import missing** |
| Lava container isolation | 🔴 "Dockerfile.lava missing" | 🟡 "Refined Lava hardware integration" (Neurochip status update) | **Market intel is more precise — container layer is the actual gap** |
| Brian2 container | 🔴 "Dockerfile.brian2 missing" | Not explicitly called out in docs | **Market intel adds this — required by Python ABI conflict rule** |
| Workspace file I/O | Not in market intel scope | 🔴 "Native load broken, native save misleading" — full plan exists | **docs/ plan not in market intel — insert in Tier 0** |
| Akida contract cleanup | Not in market intel scope | 🔴 3 remaining slices in `AKIDA_RUNTIME_ACTIONS_PLAN.md` | **docs/ plan not in market intel — insert in Tier 1** |
| Teensy deployment | Not in market intel scope | ✅ "Release-ready, E2E tested" | **Confirmed done — no action** |
| Container count (20 target) | 🔴 15 of 20, 5 missing | Not explicitly tracked in docs | **Market intel is precise — adds neurohub app + neurosim** |
| Hybrid SNN-ANN nodes | 🟡 "Not confirmed" | Not mentioned in docs | **Both agree it's future scope** |
| On-device learning viz | 🟡 "Not in frontend code" | Not mentioned in docs | **Agree — medium priority** |
| LLM-assisted CNL | "TOO EARLY (24+ months)" | "P3 — too early" | **Full agreement — do not build** |
| WASM browser sim | "Do not pursue" | "10-100× too slow" | **Full agreement — do not build** |

---

## Tier 0 — In-Flight / Must Complete Before v0.1 Ships

These are tasks actively planned in docs, partially done, or blocking release. Complete in order.

### T0-A: Workspace File I/O Repair *(docs: 2026-05-10 plan)*
**Why first**: Broken native load/save is a user-visible regression. Everything else builds on a reliable workspace foundation.

| Phase | Task | Key files |
|-------|------|-----------|
| 1 | Add `file_selector` dep; implement real native `open` / `save as` for `.cnl` | `platform_helper*.dart`, `import_text_file_picker*.dart` |
| 2 | Introduce `.neurocnl-workspace.json` format; workspace save/open round-trip | `workspace_file.dart`, `workspace_provider.dart` |
| 3 | Scope simulation cache per-file; restore on active-file switch | `pipeline_provider.dart`, workspace model |
| 4 | Add rename + comparison panel in Studio UI | `studio_screen.dart` |

**Exit criteria**: Desktop load visibly imports `.cnl`; save writes to user-chosen path; workspace reopen restores tabs and cached results.

---

### T0-B: Actionable Error Diagnostics *(docs: neurocnl_status_and_priorities.md #2)*
**Why second**: Parser already has structured errors. The work is propagating them consistently. Cheap usability win.

1. Define one shared CNL error schema (`code`, `message`, `hint`, `examples`, `line`, `raw`)
2. Apply it across: parse → validate → generate → export → simulate → deploy routes
3. Add `hint` + rewrite examples for Layer 1 and Layer 2 validation failures
4. Tests assert error payload shape, not just that a request failed

---

### T0-C: One Real Training Adapter *(docs: neurocnl_status_and_priorities.md #1)*
**Why third**: The registry scaffold is ready. One adapter unlocks the whole training → deployment story. **snnTorch** recommended first (best NIR support, MIT license, largest community).

1. Implement `SnnTorchAdapter` in `training_registry.py`
2. Wire surrogate gradient training through the existing adapter dispatch
3. Add dataset fixture (N-MNIST or DVS-Gesture — pick one to start)
4. Surface `fit()` as a thin CNL-facing method over the existing pipeline

---

### T0-D: Akida Contract Cleanup (Slices 1–3) *(docs: AKIDA_RUNTIME_ACTIONS_PLAN.md)*
**Why fourth**: Three slices are pending with explicit exit criteria. Neurobench toggle in Akida UI is currently visibly disabled.

| Slice | Task |
|-------|------|
| 1 | Mark `/map` as canonical; deprecation note on `/verify`; remove test assumptions treating `/verify` as mapping |
| 2 | Studio messaging polish — distinguish package / map / run clearly across all state labels |
| 3 | Launcher guardrail coverage for Akida host map/run; cross-module integration tests |

---

## Tier 1 — Core Platform Completeness (v0.1 → v0.2)

These tasks make NMTK's architecture complete as specified. Order within Tier 1 matters.

### T1-1: Lava Isolated Container *(market intel + docs)*
**Blocked by**: Nothing (converter is ready). **Priority signal**: Python <3.11 requirement makes this a correctness issue.

1. Write `Dockerfile.lava` (Python 3.10 base, `lava-nc` + deps)
2. Add `lava-backend` service to `docker-compose.yml` and `docker-compose.prod.yml`
3. Add module entry to `modules.json`
4. Wire `lava_io.py` converter to call the container via inter-service HTTP
5. Run `python3 -m pytest neurocnl/neurocnl/export/test_lava_integration.py`

---

### T1-2: Brian2 Isolated Container *(market intel)*
**Blocked by**: T1-1 complete (establishes the container pattern).

1. Write `Dockerfile.brian2` (Python ≥3.12, `Brian2` + deps)
2. Add `brian2-backend` service to compose files
3. Wire `brian2_io.py` to call the container
4. Add integration tests

---

### T1-3: Neurohub App Container *(market intel — container count gap)*
**Blocked by**: Nothing. `Neurohub/docker-compose.yml` only has `db`; the app server needs its own service.

1. Add `neurohub` service to `Neurohub/docker-compose.yml`
2. Confirm Neurohub app binds to the correct port and is registered in `modules.json`
3. Smoke test with `python3 scripts/backend_endpoint_smoke.py`

---

### T1-4: Expand NIR Semantic Coverage *(docs: neurocnl_status_and_priorities.md #4)*
**Blocked by**: T0-C (training adapter teaches which concepts are load-bearing). Priority order:

1. `short_term_plasticity` — most common in published models
2. `lateral_inhibition` — required for competitive learning demos
3. `homeostatic_plasticity` — needed for on-device learning story
4. `neuromodulation` — defer until specific hardware target requires it

Each concept: update lowering in `nir_exporter.py` → add test → re-run `test_materializer.py`.

---

### T1-5: High-Level `compile()` / `evaluate()` CNL API *(docs: neurocnl_status_and_priorities.md #3)*
**Blocked by**: T0-C (training adapter must exist first).

1. Add `NeuroCNL.compile(spec: str) -> NetworkIR`
2. Add `NeuroCNL.fit(spec, dataset, adapter='snntorch') -> TrainResult`
3. Add `NeuroCNL.evaluate(spec, dataset) -> BenchResult`
4. Document as the primary public-facing entry point

---

### T1-6: Upstream NeuroBench Integration *(market intel — most precise finding)*
**Blocked by**: T1-5 (`evaluate()` surface needs to exist first).

1. Add `neurobench` as optional dep in `Neurobench/neurobench/pyproject.toml` (`neurobench[tasks]`)
2. Map NMTK's `BenchmarkResult` schema to upstream `Benchmark` + `Postprocessor` interface
3. Load one upstream task dataset (MSWC or SHD) through `pynq_runner` / `synsense_runner`
4. Enable the Neurobench toggle in the Akida UI (currently hard-disabled)
5. Output results comparable to published NeuroBench leaderboards

---

### T1-7: One Event Dataset Loader *(docs: neurocnl_status_and_priorities.md #5)*
**Blocked by**: T1-6 (NeuroBench task datasets align with this).

- Target: N-MNIST or DVS-Gesture
- Wire through `Neurosense/neurosense/app/services/event_encoder.py` existing binning
- Expose as CNL-facing `dataset='n-mnist'` parameter in `evaluate()`

---

## Tier 2 — Competitive Differentiation (v0.2 → v0.3)

These tasks build the features that make NMTK visibly better than competitors in demos. No hard blockers, but each benefits from Tier 1 being stable.

### T2-1: Close the 20-Container Target
- Add `neurosim` and `neurosense` as explicit docker-compose services
- Verify total container count reaches 20
- Update `modules.json` entries

### T2-2: Quantization-Aware Training Workflow *(docs: neurocnl_status_and_priorities.md #6)*
- Exportability checks exist; quantization must become workflow-complete for Akida (1/2/4-bit) and PYNQ

### T2-3: Live Weight Visualization in Instrument Mode *(market intel)*
- On-device learning is ACT NOW per trend monitoring
- NIR layer can carry weight state; gap is the frontend display panel
- Add real-time weight/delta visualization to the Neurobench instrument surface

### T2-4: Neuro-Dream-Hand Hero Demo Polish *(market intel — "the killer demo")*
- Loihi 3 (Jan 2026) targets drone/robot control; robotic hand demo is the storytelling asset
- Polish: scripted CNL → Teensy → hand motion pipeline, fully rehearsed
- `neurodreamhand` container is already in compose — wire the demo flow end-to-end

### T2-5: Podman/Colima Support *(docs: tech stack eval)*
- Docker Desktop commercial licensing risk for teams >250 employees or >$10M revenue
- Add Podman-compatible service definitions
- Test launcher doctor with Colima as the container runtime

### T2-6: Hybrid SNN-ANN Node Type Tags *(market intel + architecture doc)*
- Add `node_type: "snn" | "ann"` tagging in the NIR exporter routing logic
- Canvas node palette: distinguish ANN layers from SNN layers
- Export routing: ANN nodes → GPU backend, SNN nodes → NIR → neuromorphic

---

## Tier 3 — Ecosystem Expansion (v0.3+)

Lower urgency; revisit after Tier 2 is complete.

| # | Task | Why it's here |
|---|------|--------------|
| T3-1 | SpiNNaker2 runner: live hardware path confirmation | `spinnaker2_runner.py` exists but hardware path unconfirmed |
| T3-2 | NEST module in App Store | Brain-scale HPC use case; not core audience |
| T3-3 | Innatera/Synfire interoperability | Only if Synfire gains traction as model exchange |
| T3-4 | Multi-chip graph partitioning | High cost, premature before single-graph semantics stable |
| T3-5 | Hybrid CPU/neuromorphic workload orchestrator | High architecture cost, weak evidence of immediate need |

---

## Tier 4 — Do Not Build Now

Explicit decisions to defer, backed by both sources.

| Task | Why not now |
|------|------------|
| LLM-assisted CNL (CNL Copilot) | P3 per tech eval. No production LLM→SNN tools exist. 24+ months out. |
| WASM browser simulation | 10-100× slower than native. Not viable for SNN workloads. |
| Neuromorphic cloud backend ("Deploy to Loihi") | SpiNNcloud/Akida Cloud/Intel NRC access — revisit 18-24 months. |
| Broad multi-framework abstraction before first adapter proven | One real adapter teaches more than a generic abstraction with no backing. |

---

## Execution Summary Table

| Tier | ID | Task | Blocked by | Est. scope |
|------|----|------|-----------|------------|
| 0 | T0-A | Workspace file I/O repair | — | Medium (4-phase plan exists) |
| 0 | T0-B | Actionable error diagnostics | — | Small (schema + propagation) |
| 0 | T0-C | First real training adapter (snnTorch) | — | Medium |
| 0 | T0-D | Akida contract cleanup (3 slices) | — | Small-Medium |
| 1 | T1-1 | Lava isolated container | — | Small (Dockerfile + wiring) |
| 1 | T1-2 | Brian2 isolated container | T1-1 | Small |
| 1 | T1-3 | Neurohub app container | — | Small |
| 1 | T1-4 | NIR semantic coverage expansion | T0-C | Medium (4 concept families) |
| 1 | T1-5 | High-level compile/evaluate API | T0-C | Small (thin wrapper) |
| 1 | T1-6 | Upstream NeuroBench integration | T1-5 | Medium |
| 1 | T1-7 | Event dataset loader (N-MNIST) | T1-6 | Small |
| 2 | T2-1 | Neurosim + Neurosense containers (close 20-container target) | T1-1, T1-2 | Small |
| 2 | T2-2 | Quantization-aware training | T0-C | Medium |
| 2 | T2-3 | Live weight visualization | T1-5 | Medium |
| 2 | T2-4 | Dream-Hand hero demo polish | T0-D | Small |
| 2 | T2-5 | Podman/Colima support | — | Small |
| 2 | T2-6 | Hybrid SNN-ANN node types | T1-4 | Medium |
| 3 | T3-x | Ecosystem expansion | Tier 2 stable | Large, long-horizon |
| 4 | — | LLM CNL, WASM, cloud deploy | — | Do not build |

---

## Key Design Constraints (Non-Negotiable)

1. **Container isolation is not optional.** Lava (<3.11) and Brian2 (≥3.12) cannot share an environment. Every backend must run in its own container. T1-1 and T1-2 are correctness issues, not optimizations.

2. **NIR fails closed.** Unsupported concepts must be rejected with a structured error, never exported dishonestly. The existing `_NIR_CONCEPT_VERDICTS` pattern is correct — extend it, don't weaken it.

3. **NeuroBench must use the upstream library.** NMTK's own `BenchmarkResult` schema can coexist, but the "trusted auditor" brand requires upstream-compatible output. Internal schema ≠ NeuroBench compliance.

4. **One training adapter proven before abstraction.** Do not build a broad multi-framework adapter layer until snnTorch is working end-to-end. The docs make this explicit.

5. **The workspace is the foundation.** T0-A (file I/O repair) must come first because broken save/load undermines every other feature.
