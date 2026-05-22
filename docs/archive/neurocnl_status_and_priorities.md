# NeuroCNL Status And Priorities

This document extracts the NeuroCNL-specific status, gaps, and priorities from:

- [unified_toolkit_architecture.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified_toolkit_architecture.md)
- [neuromorphic_computing_integration_strategy.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/neuromorphic_computing_integration_strategy.md)
- [neuromorphic_computing_six_initiatives_plan.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/neuromorphic_computing_six_initiatives_plan.md)

It is the source of truth for what is already implemented for NeuroCNL, what is still missing, and which items are worth doing now versus later.

## Scope Decision

Active product scope is now limited to `CNL -> IR -> NIR`.

- Keep: authoring, validation, honest lowering, NIR export, and NIR-backed editor/canvas coherence.
- De-prioritize from the active task queue: legacy execution backends, runtime-only work, training surfaces, benchmark-first APIs, and hardware deployment workflows.
- Historical code or docs for those broader workflows may still exist, but they are not the planning baseline for current work.

## Current Repo Status

### Implemented

- [x] Parser, validation, and unified pipeline orchestration exist in `neurocnl/neurocnl/pipeline.py`.
- [x] Direct CNL -> IR -> NIR export exists for the currently supported subset.
- [x] NIR export fails closed when the requested concepts cannot be lowered honestly.
- [x] Actionable CNL error diagnostics now use one normalized payload shape across parse, validate, generate, and export routes.
- [x] Studio-facing graph/editor synchronization groundwork exists and can be tightened around NIR as the canonical graph model.

### Partially Implemented

- [ ] NIR semantic coverage is only partial. Some parser-recognized concepts lower faithfully, some lower approximately, some are metadata-only, and some are still rejected.
- [ ] Editor, canvas, and export flows still need a single shared NIR-backed graph state to avoid silent drift.
- [ ] Workspace persistence is still more editor-session-oriented than NIR-artifact-oriented.

### Not Implemented

- [ ] No first-class user-facing `compile_to_nir()` API is documented as the primary public surface.
- [ ] No explicit `NIR -> NetworkIR -> CNL` bridge is productized as a supported round-trip path.
- [ ] No graph partitioning for multi-chip deployment.
- [ ] No quantization-aware lowering workflow.
- [ ] No hybrid CPU/neuromorphic runtime orchestrator.

## Evidence

### Core CNL Pipeline

- `neurocnl/neurocnl/pipeline.py` provides parse, validation, IR lowering, export, and planner integration for the current authoring flow.

### Honest NIR Export

- `neurocnl/neurocnl/export/nir_exporter.py` provides `materialize_to_nir()`, `summarize_nir_lowering()`, `ensure_nir_exportable()`, and `export_to_nir()`.
- Unsupported concepts are rejected explicitly rather than exported dishonestly.

### NIR Planning Groundwork

- `neurocnl/neurocnl/planner.py` already carries exportability-oriented support logic that can be narrowed further around NIR-first behavior.

### Diagnostic Groundwork

- `neurocnl/neurocnl/cnl/cnl_parser.py` already classifies parse failures into structured error details with hints and examples.
- `neurocnl/backend/app/routers/parse.py` preserves those structured parse diagnostics cleanly.
- `neurocnl/backend/app/utils/cnl_errors.py` now normalizes parse, validation, lowering, backend, and training-request failures into one route-safe schema.
- `neurocnl/backend/app/services/neurocnl_bridge.py` and the parse/generate/export routes now preserve actionable `items` with `code`, `message`, `hint`, `examples`, `line`, and `raw` when available.

## What Still Needs To Happen

### Must Do Now

- [ ] Tighten NIR support semantics and broaden lowering for the most common concept families.
Reason: portability claims become risky when too many concepts degrade silently to metadata or approximation.

- [ ] Make NIR the canonical graph state across editor, canvas, and export.
Reason: authoring quality depends on one honest shared graph model rather than parallel text/graph states.

- [ ] Productize an explicit `compile_to_nir()` surface.
Reason: the supported product promise should be visible in the API and docs, not just implicit in internal routing.

### Nice Next

- [ ] Add quantization integration where hardware targets actually need it.
Reason: exportability checks exist, but quantization remains more advisory than workflow-complete.

- [ ] Add an explicit `NIR -> CNL` summarization bridge with structured unsupported-node diagnostics.
Reason: round-trip editing needs a truthful path back to readable text.

### Probably Not Now

- [ ] Hybrid CPU/neuromorphic workload orchestration.
Reason: high architecture cost, weak evidence of immediate need, and several lower-cost CNL gaps remain open.

- [ ] Multi-chip partitioning and broad heterogeneous graph mapping.
Reason: important long-term, but premature before the single-graph semantic and training surfaces are stable.

## Recommended Execution Order

1. Expand the honest NIR subset for the most common parser-recognized concepts.
2. Make NIR the canonical graph state shared by editor, canvas, and export.
3. Add a thin user-facing `compile_to_nir()` layer and document it as the primary public surface.
4. Add an explicit `NIR -> CNL` bridge for truthful round-trip editing.
5. Revisit quantization and hybrid orchestration only after the above surfaces are stable.

## Actionable Error Diagnostics

This is now materially implemented across the backend authoring and export surface.

### What already exists

- Parse failures already carry structured fields such as `code`, `message`, `hint`, `examples`, `line`, and `raw`.
- Validation flows already have structured `checks_failed` payloads.
- The route-safe helpers now normalize error `items` across parse, validate, generate, and export flows.
- Layer 1 and Layer 2 failures now gain prescriptive `hint` and example-rewrite guidance instead of collapsing to plain strings.

### What is still missing

- Frontend affordances still need to consume the richer error categories more explicitly.
- Some deeper lowering failures still rely on generic rewrite hints rather than domain-specific remediation text.

### Recommended implementation shape

1. Define one shared CNL error schema and use it across all user-facing routes.
2. Preserve `hint`, `examples`, `line`, and `raw` everywhere parse failures can surface.
3. Add `hint` and example rewrite fields to Layer 1 and Layer 2 failures.
4. Standardize error categories so the UI can explain whether the problem is syntax, semantics, lowering, or backend support.
5. Add tests that assert error payload shape and actionable guidance, not just that a request failed.

## What To Treat As Decision Inputs, Not Commitments

The older architecture and strategy docs contain useful long-range ideas, but the following should be treated as planning hypotheses rather than current commitments unless backed by code:

- broad high-level CNL ergonomics
- compiler-grade partitioning
- hybrid runtime orchestration

## Maintenance Rule

When NeuroCNL status changes materially, update this document first and let the higher-level architecture or strategy docs link here instead of repeating detailed CNL status inline.
