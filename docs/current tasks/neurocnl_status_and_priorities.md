# NeuroCNL Status And Priorities

This document extracts the NeuroCNL-specific status, gaps, and priorities from:

- [unified_toolkit_architecture.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified_toolkit_architecture.md)
- [neuromorphic_computing_integration_strategy.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/neuromorphic_computing_integration_strategy.md)
- [neuromorphic_computing_six_initiatives_plan.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/neuromorphic_computing_six_initiatives_plan.md)

It is the source of truth for what is already implemented for NeuroCNL, what is still missing, and which items are worth doing now versus later.

## Current Repo Status

### Implemented

- [x] Parser, validation, and unified pipeline orchestration exist in `neurocnl/neurocnl/pipeline.py`.
- [x] Direct CNL -> IR -> NIR export exists for the currently supported subset.
- [x] NIR export fails closed when the requested concepts cannot be lowered honestly.
- [x] Backend support planning exists for NIR and hardware-facing targets including Akida, PYNQ, and Teensy.
- [x] Training-abstraction groundwork exists as a tested adapter registry in `neurocnl/neurocnl/training_registry.py`.
- [x] Concrete training adapters now exist: `sleep_pes` plus a surrogate-gradient `snntorch` adapter with honest optional-dependency gating.
- [x] A thin high-level `fit()` entrypoint now exists in `neurocnl/neurocnl/training_api.py` and is exported from `neurocnl`.
- [x] Actionable CNL error diagnostics now use one normalized payload shape across parse, validate, generate, export, simulate, deploy, and training-request routes.
- [x] NeuroBench-facing execution and metric-normalization groundwork already exists.
- [x] Event-data groundwork exists via NeuroSense event binning, spike-tensor conversion, and replay handoff into NeuroCNL.

### Partially Implemented

- [ ] NIR semantic coverage is only partial. Some parser-recognized concepts lower faithfully, some lower approximately, some are metadata-only, and some are still rejected.
- [ ] Training abstraction is now real but still early-stage. `snntorch` and `sleep_pes` are wired, but `evaluate()` is still missing, dataset support is still synthetic or compatibility-focused, and the frontend has not yet grown a richer adapter-specific training workflow.
- [ ] Benchmarking is integrated at the plumbing level, but not yet exposed as a first-class high-level CNL `evaluate()` surface.
- [ ] Event pipelines exist at the helper and artifact-handoff level, but not as full dataset-ready ingestion surfaces.
- [ ] The first event-training dataset is only a deterministic N-MNIST-style toy fixture for adapter bring-up, not yet a full upstream dataset loader.

### Not Implemented

- [ ] No first-class high-level `compile()` / `evaluate()` API yet.
- [ ] No concrete `SpikingJelly` or equivalent second framework adapter yet.
- [ ] No dataset loaders for N-MNIST, DVS-Gesture, or DDD17.
- [ ] No graph partitioning for multi-chip deployment.
- [ ] No quantization-aware training or integrated quantization-lowering workflow.
- [ ] No hybrid CPU/neuromorphic runtime orchestrator.

## Evidence

### Core CNL Pipeline

- `neurocnl/neurocnl/pipeline.py` provides parse, validation, IR lowering, generation, simulation, and planner integration.

### Honest NIR Export

- `neurocnl/neurocnl/export/nir_exporter.py` provides `materialize_to_nir()`, `summarize_nir_lowering()`, `ensure_nir_exportable()`, and `export_to_nir()`.
- Unsupported concepts are rejected explicitly rather than exported dishonestly.

### Backend And Hardware Support Planning

- `neurocnl/neurocnl/planner.py` provides backend support classification and deployability/exportability logic for NIR, Akida, PYNQ, and Teensy-oriented targets.

### Training Abstraction Groundwork

- `neurocnl/neurocnl/training_registry.py` provides adapter capability listing, mode validation, backend lookup, and fail-closed dispatch.
- `neurocnl/neurocnl/tests/test_training_registry.py` covers duplicate registration, normalization, supported-mode checks, and dispatch behavior.
- `neurocnl/neurocnl/training/snntorch_adapter.py` now provides a concrete surrogate-gradient adapter with honest dependency checks and a synthetic N-MNIST-style fixture.
- `neurocnl/neurocnl/training_api.py` now exposes a thin `fit(...)` convenience wrapper over the shared registry.

### NeuroBench Groundwork

- `Neurobench/neurobench/app/services/benchmark_runner.py` already executes benchmark flows and accepts NeuroSense recording-based inputs.
- `Neurobench/neurobench/app/services/metric_normalizer.py` already normalizes core backend metrics.

### Event Pipeline Groundwork

- `Neurosense/neurosense/app/services/event_encoder.py` already implements event binning and dense spike-tensor conversion.
- `Neurosense/neurosense/tests/test_event_encoder.py` covers those helpers.
- `neurocnl/backend/app/services/neurosense_artifact.py` prepares canonical NeuroSense artifacts for NeuroCNL replay workflows.

### Diagnostic Groundwork

- `neurocnl/neurocnl/cnl/cnl_parser.py` already classifies parse failures into structured error details with hints and examples.
- `neurocnl/backend/app/routers/parse.py` preserves those structured parse diagnostics cleanly.
- `neurocnl/backend/app/utils/cnl_errors.py` now normalizes parse, validation, lowering, backend, and training-request failures into one route-safe schema.
- `neurocnl/backend/app/services/neurocnl_bridge.py` and the generate/export/simulate/deploy/training routes now preserve actionable `items` with `code`, `message`, `hint`, `examples`, `line`, and `raw` when available.

## What Still Needs To Happen

### Must Do Now

- [ ] Add `compile()` and `evaluate()` beside the new `fit()` surface.
Reason: `fit()` now exists, but the public API is still incomplete for the full compile/train/evaluate story.

- [ ] Tighten NIR support semantics and broaden lowering for the most common concept families.
Reason: portability claims become risky when too many concepts degrade silently to metadata or approximation.

### Nice Next

- [ ] Add dataset-ready event loaders for N-MNIST, DVS-Gesture, and DDD17.
Reason: this makes the event pipeline usable for real workflows instead of mostly helper-level integration.

- [ ] Expand benchmark reporting into a first-class CNL evaluation surface.
Reason: the benchmark plumbing exists already, but users still need a coherent CNL-facing result surface.

- [ ] Add quantization integration where hardware targets actually need it.
Reason: exportability checks exist, but quantization remains more advisory than workflow-complete.

### Probably Not Now

- [ ] Hybrid CPU/neuromorphic workload orchestration.
Reason: high architecture cost, weak evidence of immediate need, and several lower-cost CNL gaps remain open.

- [ ] Multi-chip partitioning and broad heterogeneous graph mapping.
Reason: important long-term, but premature before the single-graph semantic and training surfaces are stable.

- [ ] Broad multi-framework abstraction before the first adapter is proven useful.
Reason: one real adapter teaches more than a generic abstraction layer with no operational backing.

## Recommended Execution Order

1. Add a thin user-facing `compile()` and `evaluate()` layer beside the new `fit()` surface.
2. Expand the honest NIR subset for the most common parser-recognized concepts.
3. Replace the synthetic N-MNIST-style fixture with one real event-dataset loader end-to-end.
4. Add quantization workflow support where current hardware targets demand it.
5. Revisit hybrid orchestration only after the above surfaces are stable.

## Actionable Error Diagnostics

This is now materially implemented across the backend CNL surface.

### What already exists

- Parse failures already carry structured fields such as `code`, `message`, `hint`, `examples`, `line`, and `raw`.
- Validation flows already have structured `checks_failed` payloads.
- The route-safe helpers now normalize error `items` across parse, validate, generate, export, simulate, deploy, and training request validation.
- Layer 1 and Layer 2 failures now gain prescriptive `hint` and example-rewrite guidance instead of collapsing to plain strings.

### What is still missing

- Frontend affordances still need to consume the richer error categories more explicitly.
- Some deeper lowering and backend-specific failures still rely on generic rewrite hints rather than domain-specific remediation text.

### Recommended implementation shape

1. Define one shared CNL error schema and use it across all user-facing routes.
2. Preserve `hint`, `examples`, `line`, and `raw` everywhere parse failures can surface.
3. Add `hint` and example rewrite fields to Layer 1 and Layer 2 failures.
4. Standardize error categories so the UI can explain whether the problem is syntax, semantics, lowering, or backend support.
5. Add tests that assert error payload shape and actionable guidance, not just that a request failed.

## What To Treat As Decision Inputs, Not Commitments

The older architecture and strategy docs contain useful long-range ideas, but the following should be treated as planning hypotheses rather than current commitments unless backed by code:

- broad high-level CNL ergonomics
- full training-library abstraction
- dataset-complete event ingestion
- compiler-grade partitioning
- hybrid runtime orchestration

## Maintenance Rule

When NeuroCNL status changes materially, update this document first and let the higher-level architecture or strategy docs link here instead of repeating detailed CNL status inline.
