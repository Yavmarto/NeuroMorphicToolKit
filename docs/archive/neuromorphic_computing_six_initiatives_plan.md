# Six Initiatives Plan

This document turns the six initiatives from [neuromorphic_computing_integration_strategy.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/neuromorphic_computing_integration_strategy.md) into a practical implementation order and execution model for the current repo.

## CNL Progress Snapshot

NeuroCNL-specific implementation status and the recommended "must do now / nice next / probably not now" split now live in [neurocnl_status_and_priorities.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/neurocnl_status_and_priorities.md).

### 1. Native NeuroBench Integration

Why first:
- The repo already has benchmark orchestration and metric plumbing in `Neurobench/neurobench/app/services/benchmark_runner.py`.
- Several runners already normalize latency, energy, and accuracy-like metrics into NeuroBench result payloads.
- This gives the fastest user-visible outcome and creates a measurement layer for later initiatives.

What to build first:
- [x] Canonical metric normalization across backend responses.
- [ ] Standard `evaluate()`-adjacent reporting surfaces for accuracy, latency, energy, and memory-related metrics where available.
- [ ] Baseline benchmark fixtures that can be reused as other initiatives land.

Main ownership:
- `Neurobench`
- `neurocnl` only where benchmark-facing execution or result semantics need coordination

Suggested Deerflow usage:
- Good fit for isolated helpers and tests.
- Poor fit for cross-module result-schema decisions.

### 2. Standardized Event Data Pipelines

Why second:
- There is already useful groundwork in `neurocnl/neurocnl/spike_encoding.py`, `Neurosense/neurosense/app/services/spike_encoder.py`, and `Neurosense/neurosense/app/services/event_encoder.py`.
- This initiative feeds directly into demos, offline replay, benchmarking, and real sensor integration.
- It creates reusable input pipelines that later abstractions can build on.

What to build first:
- [x] Event batching and spike-tensor conversion helpers.
- [ ] Common dataset ingestion surfaces for event-based data.
- [x] Stable payload shapes for replay, export, and downstream simulation.

Main ownership:
- `Neurosense`
- `neurocnl` when shared encoding semantics need to be library-level

Suggested Deerflow usage:
- Good fit for a single dataset loader or narrow preprocessing helper.
- Poor fit for end-to-end pipeline integration across acquisition, replay, and simulation.

### 3. SNN Training Abstraction Layer

Why third:
- `neurocnl` already has backend capability metadata and some conversion footholds, especially around Rockpool and Sinabs-related paths.
- This is the first initiative that starts to unify “bring your own training” instead of assuming one learning path.
- It is valuable, but still needs careful interface design before deeper implementation.

What to build first:
- [x] Adapter registry and training-mode validation.
- [x] Small capability summaries for supported training modes such as surrogate gradients or ANN-to-SNN conversion.
- [ ] One concrete adapter after the registry and validation contracts are stable.

Main ownership:
- `neurocnl`

Suggested Deerflow usage:
- Good fit for isolated registry logic, adapter stubs, and unit tests.
- Poor fit for real framework integration or architecture decisions.

### 4. CNL High-Level Abstractions

Why fourth:
- `neurocnl` already has a unified pipeline orchestration path, so a higher-level API is plausible.
- However, the interface should sit on top of stable training and evaluation behavior, not hide unstable semantics too early.

What to build first:
- [ ] Thin high-level wrappers for compile and evaluate flows.
- [ ] Tutorial-oriented ergonomic improvements.
- [ ] Clear error mapping from the existing pipeline into friendlier API surfaces.

Main ownership:
- `neurocnl`

Suggested Deerflow usage:
- Mostly local.
- Small tutorial or example drafting can be outsourced, but the public API shape should stay local.

### 5. Robust NIR Hardware Mapping

Why fifth:
- The repo already contains pieces of hardware capability modeling, quantization intent, and mapping semantics.
- But partitioning, quantization-aware lowering, and heterogeneous mapping are compiler-grade changes with high regression risk.
- This becomes more valuable once the earlier input, training, and benchmarking surfaces are stable enough to measure it.

What to build first:
- [ ] Clear partitioning requirements.
- [x] Honest support reporting for exact vs approximate lowering.
- [ ] Narrow hardware-specific quantization helpers backed by tests.

Main ownership:
- `neurocnl`
- hardware-specific consumer modules where handoff formats are affected

Suggested Deerflow usage:
- Limited to narrow helpers.
- Core mapping logic should stay local.

### 6. Hybrid Workload Support

Why sixth:
- This has the highest architecture cost and the weakest evidence of an already-present orchestrator.
- It crosses runtime, data conversion, graph partitioning, and UX boundaries.
- It benefits from the other five initiatives being more mature first.

What to build first:
- [ ] A design doc and explicit runtime boundaries.
- [ ] Minimal proof-of-concept conversion seams between dense tensors and spike tensors.
- [ ] Honest scope limits for what “hybrid” means in the first release.

Main ownership:
- `neurocnl`
- likely `Neurosim`, `Neurochip`, and launcher/control-plane surfaces if execution spans modules

Suggested Deerflow usage:
- Mostly not recommended until the local architecture is settled.

## Why This Order

The order is designed to maximize leverage while reducing integration risk:

1. Build measurement and result visibility first.
2. Standardize high-value data inputs next.
3. Add training abstraction once inputs and metrics are clearer.
4. Add ergonomic high-level APIs on top of more stable behavior.
5. Tackle harder compiler and mapping work after instrumentation exists.
6. Leave the broadest runtime orchestration problem for last.

## Local Vs Deerflow

### Keep local

- Prioritization and roadmap decisions
- Public API shape
- Cross-module contracts
- Capability claims and support-matrix semantics
- NIR mapping logic
- Hybrid runtime orchestration design
- Any work dependent on hidden runtime behavior or repo-wide context

### Good Deerflow candidates

- Small pure helpers
- One dataset loader at a time
- One adapter or registry helper at a time
- Example-driven unit test generation
- Documentation or tutorial drafts that do not invent new semantics

### Poor Deerflow candidates

- Cross-cutting refactors
- Architecture-heavy changes
- Anything requiring real logs or hidden operational behavior
- Changes that span `neurocnl`, `Neurobench`, `Neurosense`, and launcher behavior at once

## Practical Execution Split

### Initiative 1: Native NeuroBench Integration

Local:
- Result schema decisions
- service integration
- benchmark execution semantics

Deerflow:
- small metric helpers
- fixture generation
- focused unit tests

### Initiative 2: Standardized Event Data Pipelines

Local:
- canonical payload shapes
- replay/export semantics
- integration with live and recorded data paths

Deerflow:
- one event-dataset loader packet
- one preprocessing helper packet

### Initiative 3: SNN Training Abstraction Layer

Local:
- registry and capability contract design
- framework boundary decisions

Deerflow:
- isolated registry logic
- one adapter stub
- narrow validation helpers

### Initiative 4: CNL High-Level Abstractions

Local:
- public API
- error semantics
- wrapper behavior over the unified pipeline

Deerflow:
- example or tutorial drafting only

### Initiative 5: Robust NIR Hardware Mapping

Local:
- partitioning logic
- quantization semantics
- exact vs approximate support behavior

Deerflow:
- only very narrow helper logic if packetized carefully

### Initiative 6: Hybrid Workload Support

Local:
- architecture
- orchestration
- runtime boundaries

Deerflow:
- not recommended until the architecture is already frozen enough to packetize safely

## Suggested First Wave

The best first wave for this repo is:

1. [ ] Finish the small benchmark metric normalization surfaces.
2. [ ] Finish the event spike-binner and related event-data helpers.
3. [ ] Stabilize a training adapter registry and one narrow adapter path.

This sequence creates:
- measurable outputs
- reusable input data surfaces
- an extensible training abstraction foothold

without forcing an early commitment to the most expensive mapping and orchestration work.
