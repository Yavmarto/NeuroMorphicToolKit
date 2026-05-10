# Initiative 1 And 4 Scope, Initiative 5 And 6 Decomposition

This document refines Deerflow fit and execution strategy for:

- Initiative 1: Native NeuroBench Integration
- Initiative 4: CNL High-Level Abstractions
- Initiative 5: Robust NIR Hardware Mapping
- Initiative 6: Hybrid Workload Support

It is intended as a follow-on planning artifact to [neuromorphic_computing_six_initiatives_plan.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/neuromorphic_computing_six_initiatives_plan.md).

## Summary

### Initiative 1

Best handled as a bounded Deerflow packet after local scoping. Good candidate for one large packet if we keep it focused on result normalization, evaluation plumbing, and benchmark-facing helper surfaces instead of broad product redesign.

### Initiative 4

Local-first for API design, then a bounded Deerflow packet for implementation of thin high-level wrappers and examples once semantics are frozen.

### Initiative 5

Do not send as one large Deerflow task. Decompose into multiple small, reviewable local-first slices. Deerflow may help on selected helper slices only after semantics are explicit.

### Initiative 6

Strongly local-first. Start with architecture and contract decisions. Deerflow becomes useful only after runtime boundaries and first supported hybrid topology are already decided.

## Initiative 1 Scope

### Goal

Turn existing benchmark execution and metric plumbing into a more coherent, measurable evaluation surface without changing suite-visible semantics accidentally.

### Repo anchors

- `Neurobench/neurobench/app/services/benchmark_runner.py`
- `Neurobench/neurobench/app/services/target_comparator.py`
- `Neurobench/neurobench/app/runners/*.py`
- `Neurobench/neurobench/app/services/diff_engine.py`
- `Neurobench/neurobench/contracts/*`

### Recommended scope boundary

In scope:

- metric normalization and canonical result handling
- benchmark runner helper cleanup
- target comparison helper consistency
- baseline and diff-adjacent service cleanup
- focused benchmark fixtures and tests

Out of scope for the first Deerflow packet:

- frontend redesign
- broad report-generation changes
- new cross-module result contracts
- end-to-end suite-wide publishing flows

### Why this is a medium-fit Deerflow task

This initiative has a good amount of implementation-heavy service work, but it also touches suite-visible semantics. The safest shape is:

1. scope locally
2. freeze acceptance criteria
3. packetize the service-layer phase
4. verify and reconcile locally

### Proposed bounded Phase 1 packet

Packet title:
- `initiative-1-neurobench-evaluation-foundation`

Suggested deliverables:

- one benchmark result normalization helper
- one comparison/metric-extraction cleanup pass
- small runner consistency pass
- unit tests for result precedence, defaults, and invalid values

Success gate:

- benchmark service tests pass
- no result-schema drift beyond explicitly approved fields

## Initiative 4 Scope

### Goal

Provide higher-level CNL entry points that feel simpler for users without hiding dishonest semantics or bypassing the existing pipeline truthfully.

### Repo anchors

- `neurocnl/neurocnl/pipeline.py`
- `neurocnl/backend/app/routers/export.py`
- existing CLI and helper scripts such as `Neuro-Dream-Hand/scripts/compile_cnl.py`
- `neurocnl/docs/ADR-claude/0006-unified-pipeline-orchestration.md`

### Recommended scope boundary

In scope:

- thin high-level wrappers for compile/evaluate-style flows
- wrapper-level validation and error shaping
- examples and tutorial-oriented usage helpers
- tests for wrapper behavior over the existing pipeline

Out of scope for the first Deerflow packet:

- inventing a full Keras-like training runtime
- new backend semantics
- broad parser or IR redesign
- user-facing API naming decisions that are still unsettled

### Why this is local-first then Deerflow

This initiative is very sensitive to API shape. The implementation work is not the risky part; the interface decisions are. So the right sequence is:

1. design API locally
2. freeze method names and expected behavior
3. hand Deerflow a bounded wrapper implementation packet

### Proposed bounded Phase 1 packet

Packet title:
- `initiative-4-cnl-high-level-wrapper-foundation`

Suggested deliverables:

- one wrapper module over the unified pipeline
- compile/evaluate-style façade methods
- exact error/return-shape tests
- one tutorial-style example test or example script

Success gate:

- wrapper tests pass
- no hidden bypass of planner, validator, or pipeline semantics

## Initiative 5 Decomposition

### Goal

Improve NIR hardware mapping honestly, especially around materialization truthfulness, quantization semantics, structured connectivity, and hardware-aware lowering.

### Repo anchors

- `neurocnl/neurocnl/ir/materializer.py`
- `neurocnl/neurocnl/export/nir_exporter.py`
- `neurocnl/neurocnl/backends/capabilities.py`
- `neurocnl/docs/support_matrix.md`
- hardware-adjacent quantization helpers across the repo

### Why not one big Deerflow pass

This is compiler-like work with high semantic risk. A large external pass would likely:

- blur exact vs approximate lowering
- miss support-matrix sync points
- create subtle drift between exporter, materializer, planner, and docs

### Decomposition

#### 5A. Dense tensor truthfulness

Scope:

- preserve exact dense matrices
- keep summary buckets honest
- make emitted tensor classes match reported classes

Fit:

- small Deerflow packet possible

Gate:

- materializer tensor-truthfulness tests pass

#### 5B. Quantization semantics

Scope:

- centralize weight quantization decisions for target-specific mapping
- document exact vs quantized support claims

Fit:

- local-first

Gate:

- capability and exporter tests stay aligned

#### 5C. Structured connectivity expansion

Scope:

- one structured pattern at a time beyond current subset
- explicit fail-closed behavior for unsupported patterns

Fit:

- small Deerflow packet per pattern after semantics are frozen

Gate:

- regression tests and support docs updated together

#### 5D. Shape-aware validation beyond flattened counts

Scope:

- population shape semantics
- validation and materialization alignment

Fit:

- local-first

Gate:

- materializer/exporter/validation agreement on shape handling

#### 5E. Convolution and pooling contracts

Scope:

- explicit contract design before implementation

Fit:

- local design only at first

Gate:

- design checkpoint approved before coding

### Deerflow recommendation for Initiative 5

Use Deerflow only for narrow sub-slices like `5A` or one part of `5C`. Do not package all of Initiative 5 together.

## Initiative 6 Decomposition

### Goal

Enable mixed conventional and neuromorphic execution in a way that is explicit, bounded, and honest about what is supported.

### Repo anchors

- `neurocnl/neurocnl/converter/*`
- `Neurosim/neurosim/app/services/preview_runner.py`
- `Neurochip/neurochip/app/services/*`
- `Neurobench/neurobench/app/runners/*`
- launcher and execution-control surfaces where cross-runtime orchestration would eventually matter

### Why this is the weakest Deerflow fit today

This initiative depends on unresolved architecture:

- what counts as a hybrid graph
- where tensor-to-spike and spike-to-tensor conversion lives
- what runtime owns orchestration
- which first topology is supported

Without those decisions, a large Deerflow pass would mainly invent structure.

### Decomposition

#### 6A. Architecture definition

Scope:

- define supported hybrid topologies
- define runtime ownership
- define data-conversion boundaries

Fit:

- local only

Gate:

- written architecture note or ADR approved

#### 6B. Conversion contract helpers

Scope:

- spike-to-tensor and tensor-to-spike contract definitions
- shape and timing semantics for conversions

Fit:

- local-first, small Deerflow packet possible afterward

Gate:

- exact conversion contract examples approved

#### 6C. Minimal proof-of-concept execution path

Scope:

- one supported hybrid graph shape
- one narrow execution path

Fit:

- maybe Deerflow after `6A` and `6B` are settled

Gate:

- proof-of-concept tests pass for the selected topology

#### 6D. Planner and surfacing integration

Scope:

- planner support verdicts
- UI/API surfacing of hybrid support level

Fit:

- local-first

Gate:

- planner and surfacing agree on supported topology claims

### Deerflow recommendation for Initiative 6

Do not create a Deerflow packet yet for the whole initiative. First complete `6A`. After that, packetize `6B` or `6C` separately.

## Recommended Next Packets

If we continue the Deerflow-heavy approach, the best next packets after Initiatives 2 and 3 are:

1. `initiative-1-neurobench-evaluation-foundation`
2. `initiative-4-cnl-high-level-wrapper-foundation`

And the best local-first decomposition tasks are:

1. `initiative-5A-dense-tensor-truthfulness`
2. `initiative-5B-quantization-semantics`
3. `initiative-6A-hybrid-architecture-definition`

## Decision Matrix

| Initiative | Best next move | Deerflow fit | Notes |
|---|---|---|---|
| 1 | Scope locally, then one bounded packet | Medium | Good for service-layer implementation, weaker for contract decisions |
| 4 | Freeze API locally, then packetize wrappers | Medium | API shape must be decided first |
| 5 | Decompose into local-first slices | Low as one packet | Use Deerflow only on narrow sub-slices |
| 6 | Architecture first, packetize later | Very low today | Do not outsource unresolved runtime boundaries |
