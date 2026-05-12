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
- [x] NeuroBench-facing execution and metric-normalization groundwork already exists.
- [x] Event-data groundwork exists via NeuroSense event binning, spike-tensor conversion, and replay handoff into NeuroCNL.

### Partially Implemented

- [ ] NIR semantic coverage is only partial. Some parser-recognized concepts lower faithfully, some lower approximately, some are metadata-only, and some are still rejected.
- [ ] Training abstraction is only scaffold-level. The registry exists, but no concrete framework adapter was found.
- [ ] Benchmarking is integrated at the plumbing level, but not yet exposed as a first-class high-level CNL `evaluate()` surface.
- [ ] Event pipelines exist at the helper and artifact-handoff level, but not as full dataset-ready ingestion surfaces.
- [ ] Actionable error diagnostics are only partially implemented. Parser failures already carry structured `code`, `message`, `hint`, `examples`, `line`, and `raw` fields, but several downstream routes still collapse failures into plain strings or message lists, and validation failures are not yet consistently prescriptive.

### Not Implemented

- [ ] No first-class high-level `compile()` / `fit()` / `evaluate()` API.
- [ ] No concrete `snnTorch`, `SpikingJelly`, or equivalent training adapters.
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
- `neurocnl/backend/app/services/neurocnl_bridge.py` also preserves structured parse diagnostics for validation flows.
- Several other routes still reduce failures to strings or plain message arrays, so the guidance is not yet consistent across the full CNL surface.

## What Still Needs To Happen

### Must Do Now

- [ ] Add one real training adapter.
Reason: the registry scaffold is already in place, so this is the shortest path from architecture to actual user capability.

- [ ] Add a thin high-level CNL API over the existing pipeline.
Reason: the core pipeline already exists, but the public surface is still too low-level if CNL is meant to be the primary entrypoint.

- [ ] Tighten NIR support semantics and broaden lowering for the most common concept families.
Reason: portability claims become risky when too many concepts degrade silently to metadata or approximation.

- [ ] Make parse and validation failures consistently actionable across all CNL routes.
Reason: the parser already has the right structured error model, so this is a realistic near-term usability win and one of the cheapest ways to reduce user confusion.

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

1. Implement one real training adapter end-to-end.
2. Make parse and validation failures consistently actionable across parse, validate, generate, export, simulate, and deploy routes.
3. Add a thin user-facing `compile()` and `evaluate()` layer over the existing pipeline.
4. Expand the honest NIR subset for the most common parser-recognized concepts.
5. Add one event dataset loader end-to-end.
6. Add quantization workflow support where current hardware targets demand it.
7. Revisit hybrid orchestration only after the above surfaces are stable.

## Actionable Error Diagnostics

This is a realistic feature to build soon because the parser already contains most of the necessary scaffolding.

### What already exists

- Parse failures already carry structured fields such as `code`, `message`, `hint`, `examples`, `line`, and `raw`.
- Validation flows already have structured `checks_failed` payloads.
- The `/api/parse` and `/api/validate` paths preserve more structure than several of the other CNL routes.

### What is still missing

- A single error contract used consistently across parse, validate, generate, export, simulate, and deploy.
- Preservation of structured error details instead of flattening them to strings or `messages` arrays.
- Prescriptive hints and example rewrites for Layer 1 and Layer 2 validation failures, not just parser failures.
- Clear separation between parse errors, semantic validation failures, lowering failures, and backend-support failures.

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
