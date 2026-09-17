# CNL to NIR Array Support Plan

## Purpose

This document replaces the older array-support proposal with a plan that matches the current codebase.

NeuroCNL already has a direct `CNL -> IR -> NIR` path. The immediate problem is not the absence of NIR export. The immediate problem is that the current bridge is semantically narrower than both the parser surface and the longer-term goals for tensor-native NIR graphs.

This plan therefore does two things:

1. Correct the baseline assumptions about what already exists.
2. Preserve the original array-support goal as a later expansion phase once the current bridge is made honest and stable.

## Current State

### What already exists

- NeuroCNL can already compile directly to NIR without using Nengo.
- `compile_to_nir()` lowers parsed CNL to `NetworkIR` and exports it through `export_to_nir()`.
- The current materializer emits:
  - `nir.Input`
  - `nir.Output`
  - `nir.LIF`
  - `nir.Linear`
- Population dimensions are inferred from `size` or `dimensions`.
- STDP and related connection semantics are preserved as metadata.
- Integration coverage exists for the direct `CNL -> IR -> NIR` path.

### What is still missing

- The parser surface is broader than IR lowering.
- The IR surface is broader than executable NIR semantics.
- The materializer currently approximates many structures as dense scalar-filled `nir.Linear` matrices.
- Delays, learning rules, and several higher-order concepts are preserved as metadata rather than executable NIR graph nodes.
- Tensor-native shapes, structured sparsity, and operator-specific lowering are still absent.
- Capability reporting is now broadly aligned, but phase-level planning and test coverage still need to catch up with that alignment.

### Code-backed baseline as of 2026-05-07

The current plan should be read against the code that exists today:

- `neurocnl/neurocnl/backends/capabilities.py`
  - defines a real `nir` capability profile
  - marks `refractory_period`, `axonal_delay`, `stdp_learning`, `population_coding`, `network_topology`, and `timing_declaration` as `approximate`
  - explicitly declares `first_class_delay_nodes`, `first_class_learning_rules`, and `structured_sparse_connectivity` as unsupported features
- `neurocnl/neurocnl/export/nir_exporter.py`
  - routes `NetworkIR` through `Materializer().materialize(...)`
  - still supports legacy Nengo-to-NIR conversion as a separate path
- `neurocnl/neurocnl/ir/materializer.py`
  - infers population dimension from `size` or `dimensions`
  - emits only `nir.Input`, `nir.Output`, `nir.LIF`, and `nir.Linear`
  - synthesizes weights via `np.full((target_size, source_size), ...)`
  - stores refractory period, delay, provenance, and learning rules in metadata rather than as executable NIR operators
- `neurocnl/neurocnl/export/test_nir_integration.py`
  - already covers the direct `compile_to_nir()` pipeline and confirms it bypasses Nengo generation

This means the main remaining work is not "add NIR export". The main remaining work is "make the existing export semantically explicit, then expand it honestly."

## Design Principles

- Do not describe the current state as if CNL->NIR is unimplemented.
- Do not widen the grammar before making current fidelity claims honest.
- Distinguish clearly between:
  - executable NIR semantics
  - metadata-only preservation
  - unsupported export
- Treat tensor-native array support as an expansion phase, not the starting point.

## Phase 1: Make the Existing Bridge Honest

Goal: align docs, planner behavior, and export behavior with the code that actually exists today.

Status update (2026-05-07): complete.

Work:

- Added an explicit `nir` backend profile to `neurocnl/neurocnl/backends/capabilities.py`.
- Marked current NIR export as `approximate` rather than `faithful`.
- Aligned:
  - `neurocnl/docs/support_matrix.md`
  - planner output
  - backend export headers
- Documented the current honest subset:
  - executable `Input` / `Output` / `LIF` / dense `Linear`
  - faithful threshold, decay, signed dense weight, and basic I/O topology semantics
  - metadata-backed refractory period, axonal delay, STDP, and timing declarations
  - approximate topology/connectivity semantics when the source model is structured or sparse

Why first:

- This is the highest-value correction for users and downstream consumers.
- It prevents the repo from overclaiming fidelity while still allowing NIR export to remain useful.

## Phase 2: Make Partial Lowering Explicit

Goal: prevent parser-recognized concepts from being silently underrepresented in NIR export.

Status update (2026-05-07): in progress.

Work:

- Introduce concept-level export/lowering verdicts such as:
  - `lowered_faithfully`
  - `lowered_as_metadata`
  - `not_lowered`
- Extend the IR or lowering result to carry these verdicts.
- For every parser-recognized concept, define whether it is:
  - first-class in IR and NIR
  - IR-backed but metadata-only in NIR
  - rejected for NIR export
- Fail closed when a concept is parser-recognized but cannot be represented honestly in NIR.

Progress update (2026-05-07):

- The low-risk set is no longer blanket-rejected by `compile_to_nir()`.
- `population_coding_range`, `adaptive_spiking`, `receptor_dynamics`, and `background_noise`
  now lower into IR and survive NIR export as explicit metadata-backed semantics.
- The current honest verdict for this first slice is:
  - `population_coding_range` -> `lowered_as_metadata`
  - `adaptive_spiking` -> `lowered_as_metadata`
  - `receptor_dynamics` -> `lowered_as_metadata`
  - `background_noise` -> `lowered_as_metadata`
- These concepts are exportable for NIR with warnings, but they are still not executable NIR
  operators in the materialized graph.

Why before tensor grammar work:

- The current correctness risk is silent semantic loss, not lack of array syntax.

## Phase 3: Improve the Existing Materializer

Goal: strengthen the current `NetworkIR -> NIRGraph` bridge before expanding the language.

Status update (2026-05-07): started, but still materially incomplete.

What already landed:

- `Materializer.summarize_lowering(...)` now returns a typed `NirLoweringSummary`.
- The exported graph metadata already includes:
  - concept-level lowering verdicts
  - connection summary counts
  - metadata-only summary counts
  - warning strings for known approximations
- Structured-intent connections are now explicitly called out as metadata-only approximations
  instead of being silently treated as ordinary dense projections.
- Graph-level NIR metadata now preserves typed `timing_declarations` entries so advisory timing
  semantics are exposed explicitly rather than only through summary counts and warnings.
- Population-, connection-, and graph-level metadata now also expose a reserved
  `advisory_semantics` block so downstream consumers can read metadata-only semantics through a
  stable path instead of inferring them from scattered top-level fields.
- The backend NIR export response headers now expose advisory summary counts for
  structured-intent metadata-only connections, timing declarations, and shape-bearing populations,
  plus an explicit `advisory_semantics` presence marker for additive client-side diagnostics.
- Axonal delay now lowers to executable `nir.Delay` nodes for delayed projections, including
  connections that inherit a declared global default axonal delay.

What remains incomplete:

- `_synthesise_weight(...)` still expands all connections through `np.full(...)`, so the graph
  metadata is now more honest than the executable weight tensors themselves.
- The current `dense_matrix` summary bucket still mixes together:
  - genuine dense matrices
  - heuristic reshapes or resizes
  - structured intent that was flattened into dense weights
- Learning and timing semantics are still advisory only.

Work:

- Replace metadata-only delay handling with explicit `nir.Delay` lowering where supported.
- Distinguish broadcast scalar weights from genuine dense connectivity at both summary and tensor level.
- Preserve explicit dense matrices when IR already carries them instead of defaulting everything to
  `np.full(...)`.
- Preserve sparse or structured connectivity instead of collapsing all non-scalar intent into
  dense fallback tensors.
- Make timing declarations machine-checked in the materialized graph.
- Standardize metadata for non-executable semantics so downstream converters can consume it consistently.

Immediate implementation slice:

- keep the existing typed lowering-summary object, but make the bucket definitions executable and stable
- classify each connection as exactly one of:
  - scalar broadcast
  - explicit dense matrix
  - resized/heuristic matrix
  - metadata-only structured intent
- stop counting a connection as `dense_matrix` unless the emitted tensor really came from an explicit
  dense matrix in IR
- reserve explicit metadata keys for:
  - `delay`
  - `learning_rules`
  - `timing_declaration`
  - `connectivity_pattern`
  - `shape_intent`

Success criteria:

- A reviewer can inspect the generated NIR graph and tell which semantics are executable versus advisory.
- The planner and exporter report the same fidelity story.

## Phase 4: Expand the Existing CNL->IR Semantic Surface

Goal: close the current parser->IR gap before adding wholly new tensor-native sentence families.

Status update (2026-05-07): parser surface exists; IR and NIR coverage remain partial.

Priority concepts from the current parser surface:

1. `population_coding_range`
2. `background_noise`
3. `spatial_connectivity`
4. `lateral_inhibition`
5. `adaptive_spiking`
6. `receptor_dynamics`
7. `short_term_plasticity`
8. `homeostatic_plasticity`
9. `neuromodulation`

For each concept:

- define the IR shape
- define planner semantics
- define NIR lowering behavior
- define whether the result is faithful, approximate, or metadata-only
- add tests

Suggested execution order inside this phase:

1. `population_coding_range`
2. `adaptive_spiking`
3. `receptor_dynamics`
4. `background_noise`
5. `lateral_inhibition`
6. `spatial_connectivity`
7. `short_term_plasticity`
8. `homeostatic_plasticity`
9. `neuromodulation`

Why this order:

- The first four concepts are already close to existing neuron or connection parameter semantics.
- The later five concepts require either topology-aware lowering, new metadata conventions, or explicit approximation policy.

Progress update (2026-05-07):

- Step 1 of the low-risk set is now implemented for NIR honesty:
  `population_coding_range`, `adaptive_spiking`, `receptor_dynamics`, and `background_noise`
  lower to IR and export as metadata-backed NIR semantics.
- Remaining work in this phase is to decide whether any of these should later become executable
  NIR operators rather than staying metadata-only, then continue with
  `lateral_inhibition`, `spatial_connectivity`, `short_term_plasticity`,
  `homeostatic_plasticity`, and `neuromodulation`.

Why this phase matters:

- It closes already-exposed gaps in the current grammar before introducing additional language complexity.

## Phase 5: Add Tensor-Native Array Support

Goal: preserve the original ambition of the old plan once the base bridge is trustworthy.

Status update (2026-05-07): deferred by design until phases 2 through 4 are complete enough to prevent silent semantic loss.

This is where the original array-support direction belongs.

### 5.1 Multi-dimensional Populations

Add first-class support for population shapes rather than only scalar size/dimension inference.

Status update (2026-05-08): started with an IR-first slice; explicit population shape now exists as
typed IR and survives NIR export as first-class metadata, but executable node sizing still flattens
shape to a scalar neuron count.

Examples:

- `Population A forms a 28x28 grid of neurons.`
- `Population A has shape (28, 28, 1).`

IR changes:

- extend `PopulationIR` with an explicit `shape`
- define compatibility rules between `size`, `dimensions`, and `shape`
- add lowering and validation rules for shape-aware populations

Validation rules to define explicitly:

- `size == product(shape)` when both are present
- `dimensions` must mean representation dimensionality, not tensor rank
- scalar-only legacy populations remain valid with `shape=None`

Materializer changes:

- preserve shape as first-class NIR-relevant structure
- validate shape compatibility across producers and consumers

What landed in the current slice:

- `PopulationIR` now has an explicit `shape`
- `population_coding` lowering can carry `with shape (...)`
- materialization validates `size == product(shape)` when both are present
- parser and `/api/parse` contracts now surface typed `shape` metadata instead of requiring
  downstream consumers to recover it from prose conditions
- exported NIR graph metadata now exposes:
  - per-population `shape`
  - per-population `shape_intent`
  - graph-level `population_shapes`
- lowering summaries now count shape-bearing populations as metadata-backed semantics

What remains incomplete:

- executable NIR nodes still use flattened counts rather than tensor-aware operators
- shape compatibility is now enforced for the first structured-connection slice, but not yet
  propagated through downstream consumers or future tensor operators

### 5.2 Structured and Sparse Connectivity

Add first-class connectivity patterns instead of collapsing all projections to dense matrices.

Examples:

- `Connect Population A to Population B one-to-one.`
- `Connect Population A to Population B with 20% random sparsity.`
- `Connect Population A to Population B within a local radius of 2.`

IR changes:

- extend `ConnectionIR` to represent dense, sparse, local, and one-to-one patterns
- preserve masks, density, or locality parameters explicitly

Materializer changes:

- generate structurally accurate sparse or masked forms when NIR or downstream tooling supports them
- fall back only with explicit downgrade reporting

Minimum viable subset:

- one-to-one
- explicit binary mask
- scalar local-radius metadata with rejection when executable lowering is unavailable

Status update (2026-05-08): started with an IR-first structured-connectivity slice.

What landed:

- `ConnectionIR` now has first-class structured connectivity fields:
  - `connectivity_pattern`
  - `connectivity_mask`
  - `locality_radius`
  - `connection_density`
- `spatial_connectivity` now lowers into IR instead of stopping at parser recognition.
- The materializer now:
  - lowers `one_to_one` into executable diagonal dense weights
  - lowers explicit binary masks into executable masked dense weights
  - rejects first-class `local_radius` lowering with an explicit error because the current NIR bridge
    still lacks an honest executable locality operator
- NIR metadata and lowering summaries now distinguish:
  - `structured_one_to_one`
  - `structured_binary_mask`
  - `structured_intent_metadata_only`

What remains incomplete:

- random sparsity and locality-aware executable lowering are still absent
- downstream consumers still treat these patterns as advisory metadata rather than typed operators

Status update (2026-05-08): parser and API contract coverage now expose the minimum viable subset.

What landed after the IR-first slice:

- parser grammar now accepts one-to-one structured-connectivity sentences
- parser grammar now accepts explicit binary-mask structured-connectivity sentences
- parser grammar now accepts percentage-based random-sparsity structured-connectivity sentences
- parse/API contracts now surface `connectivity_pattern` and `connectivity_mask`
- parse/API contracts now also surface `locality_radius` for `local_radius` sentences and use
  typed connectivity-pattern tags for the non-executable locality and distance-dependent forms
- parse/API contracts now also surface `connection_density` for percentage-based random sparsity
  while keeping current NIR export fail-closed for that non-executable pattern
- NIR export headers now expose structured one-to-one and structured binary-mask counts so API
  consumers can distinguish executable structured connectivity from metadata-only approximations

### 5.3 Convolution and Pooling

Add tensor-native operations that cannot be honestly represented as generic dense projections.

Examples:

- `Connect Population A to Population B using a 3x3 convolutional filter with stride 1 and padding 1.`
- `Connect Population A to Population B using max pooling over a 2x2 window.`

IR changes:

- introduce explicit operation-specific IR for conv and pooling-style transforms
- store kernel size, stride, padding, channels, and output-shape rules

Materializer changes:

- lower to explicit `nir.Conv`-style nodes if supported
- validate output shapes against downstream populations
- reject unsupported tensor operators rather than misrepresenting them as dense `nir.Linear`

Guardrail:

- do not add convolution sentence families until the IR contract and export failure semantics exist first

### 5.4 Shape-Aware Validation

Once multi-dimensional populations and tensor operators exist, validation must move beyond scalar population counts.

Work:

- add shape propagation rules
- enforce operator output shape checking
- reject incompatible pipelines early

## Phase 6: Round-Trip and Consumer Validation

Goal: prove both the current semantic bridge and the later tensor-native extensions behave honestly.

Status update (2026-05-07): basic `compile_to_nir()` coverage exists; phase-complete coverage does not.

Work:

- Add tests for the current supported subset:
  - simple feedforward
  - inhibitory projection
  - delay lowering
  - STDP metadata
  - branching topology
  - input/output populations
- Add negative tests for parser-recognized but non-exportable concepts.
- Add tests for the future tensor-native subset:
  - shape-aware populations
  - sparse connectivity
  - one-to-one mappings
  - convolution lowering
  - shape mismatch rejection
- Add downstream consumer tests where practical:
  - `CNL -> IR -> NIR`
  - `NIR -> consumer conversion`

Recommended file targets:

- `neurocnl/neurocnl/export/test_nir_integration.py`
- a new materializer-focused test module under `neurocnl/neurocnl/ir/`
- planner/support reporting tests for `nir` capability verdicts
- converter smoke tests only where the optional dependency exists

Acceptance gates for this phase:

- every NIR-exportable parser concept must have at least one positive coverage path
- every parser-recognized but `not_lowered` concept must have at least one fail-closed test
- graph metadata assertions must verify the lowering summary, not only node count or file existence
- consumer tests must assert that metadata-only semantics stay metadata-only and are not misreported
  as executable behavior downstream

## Phase 7: Product and API Surfacing

Goal: expose fidelity clearly to users.

Status update (2026-05-07): partially done in docs and backend capability profiles, not yet complete at per-concept export API level.

Work:

- Return per-concept fidelity annotations from export APIs.
- Show `faithful`, `metadata-only`, and `unsupported` states in Studio export flows.
- Distinguish "valid NIR file" from "fully executable graph semantics" in UI messaging.

Suggested API shape:

- export responses should include:
  - `backend_support`
  - `nir_lowering_summary`
  - `concept_verdicts`
  - `warnings`
- the backend route should treat these as first-class response fields rather than burying them in
  free-form report text

UI acceptance criteria:

- a user exporting NIR from Studio can tell, without reading source code, whether a concept was:
  - lowered faithfully
  - lowered approximately
  - preserved as metadata only
  - rejected
- exporter success messaging must never imply hardware or simulator executability when the artifact
  is only an interchange graph with advisory metadata

## Cross-Cutting Sync Points

Whenever this plan advances, the following surfaces need to stay in sync in the same change:

- `neurocnl/neurocnl/backends/capabilities.py`
- `neurocnl/neurocnl/export/nir_exporter.py`
- `neurocnl/neurocnl/ir/materializer.py`
- `neurocnl/backend/app/routers/export.py`
- `neurocnl/docs/support_matrix.md`
- planner, exporter, and materializer regression tests

If one of these changes without the others, the likely result is a familiar failure mode for this
repo: docs say one thing, planner says another, and the materialized graph says a third.

## Concrete Next Slices

The next useful increments should be small, reviewable, and test-backed.

### Slice A: Make Phase 3 truthful at tensor level

Scope:

- stop flattening explicit dense matrix weights through scalar `np.full(...)` synthesis
- tighten connection summary buckets so they describe emitted tensors, not just IR intent
- add regression tests that inspect both emitted weights and `nir_lowering_summary`

Success bar:

- a reviewer can differentiate scalar broadcast from explicit matrix lowering by inspecting the graph
  alone

### Slice B: Finish Phase 2 fail-closed coverage

Status update (2026-05-07): complete.

Scope:

- add negative tests for `lateral_inhibition`, `spatial_connectivity`,
  `short_term_plasticity`, `homeostatic_plasticity`, and `neuromodulation`
- confirm `ensure_nir_exportable()` rejects them with stable, concept-specific messages

What landed:

- `neurocnl/neurocnl/export/test_nir_integration.py` now covers the full unsupported
  parser-recognized concept set for both:
  - direct `ensure_nir_exportable()` rejection
  - end-to-end `compile_to_nir()` fail-closed rejection
- each rejection assertion matches the specific concept id so the export path cannot regress back to
  vague or concept-agnostic failures without test breakage

Success bar:

- parser-recognized but unsupported concepts no longer rely on manual inspection to detect semantic
  loss

### Slice C: Promote one metadata-only concept into a fully specified contract decision

Status update (2026-05-08): complete for `receptor_dynamics`.

Scope:

- pick exactly one of:
  - `population_coding_range`
  - `adaptive_spiking`
  - `receptor_dynamics`
  - `background_noise`
- decide whether it should remain permanently metadata-only for NIR or gain a future executable
  lowering path
- encode that decision in docs, planner behavior, and tests

What landed:

- `receptor_dynamics` is now treated as a stable metadata-only contract for the current NeuroCNL
  NIR bridge.
- Planner warnings for backend `nir` now say this explicitly instead of describing
  `receptor_dynamics` with only the generic `approximate` label.
- Regression coverage now asserts that `run_pipeline(..., backend="nir")` surfaces the explicit
  metadata-only policy warning for receptor dynamics.
- Support docs now distinguish this policy decision from the other low-risk metadata-only concepts,
  which may still gain different future decisions later.

Decision rationale:

- The current materializer intentionally emits only `Input`, `Output`, `LIF`, and `Linear` nodes.
- Within that operator scope, receptor type and synaptic time constant can be preserved honestly as
  advisory metadata for downstream consumers, but not as executable NIR synapse behavior.
- That makes `receptor_dynamics` a better candidate for an explicit stable metadata-only contract
  than the still more open-ended population-level concepts.

Success bar:

- one previously ambiguous concept has a stable long-term policy instead of sitting indefinitely in
  a vague "later" bucket

### Slice D: Start Phase 5.1 with IR-first population shape support

Status update (2026-05-08): complete.

Scope:

- add first-class `shape` to `PopulationIR`
- allow the current `population_coding` sentence family to carry `with shape (...)`
- validate `size == product(shape)` during materialization
- preserve shape in exported NIR metadata and lowering summaries without overclaiming executable
  tensor semantics

What landed:

- shape-aware population lowering is now test-backed across parser, IR, and materializer layers
- NIR export now records shape intent explicitly at both node and graph level
- the fidelity story remains honest: shape is preserved as metadata while executable node sizing
  still flattens to scalar neuron counts

Success bar:

- a reviewer can inspect the lowered IR or exported NIR metadata and recover intended population
  shape without inferring it from neuron count alone

## Explicit Non-Goals

This plan revision does not propose:

- widening the grammar first and hoping lowering catches up later
- calling metadata-preserved semantics "faithful" just because they survive export
- treating a valid `.nir` file as proof of executable parity with the source CNL model
- adding tensor-native convolution or pooling syntax before shape and failure semantics exist

## Dependency Map

The phases above are ordered, but the actual implementation work breaks into a few coupled
dependency chains.

### Chain 1: Honesty and fail-closed behavior

Required before any array-syntax expansion:

1. concept verdicts remain complete for every parser-recognized concept
2. unsupported concepts fail closed during NIR export
3. planner, exporter, and support docs report the same verdicts

Reason:

- without this chain, new syntax increases semantic ambiguity faster than the repo can document it

### Chain 2: Materializer truthfulness

Required before structured connectivity work:

1. emitted tensors reflect IR intent more accurately than they do today
2. connection summary buckets describe emitted graph structure, not just metadata
3. structured or heuristic fallback is always visible in graph metadata and tests

Reason:

- if dense fallback remains opaque, sparse or local connectivity work will appear to succeed while
  still collapsing into misleading `nir.Linear` tensors

### Chain 3: Shape contract

Required before convolution and pooling work:

1. `PopulationIR` has a stable first-class shape contract
2. validation distinguishes population size, representation dimensions, and tensor shape
3. materializer and export APIs can expose shape intent without guessing

Reason:

- operator nodes are not safe to introduce until the repo has a single meaning for shape

### Chain 4: Consumer compatibility

Required before any claim of usable tensor-native NIR authoring:

1. downstream consumers tolerate the new metadata keys and summary fields
2. converter or consumer smoke tests confirm metadata-only semantics stay advisory
3. UI and API surfaces present truthful user messaging for mixed-fidelity graphs

Reason:

- otherwise NeuroCNL may become internally more accurate while downstream tooling becomes less
  predictable

## Deliverables Matrix

Each phase should produce explicit artifacts, not just code movement.

### Phase 2 deliverables

- stable concept verdict table in code
- fail-closed exporter behavior for `not_lowered` concepts
- regression tests covering positive and negative verdict cases
- docs that match the exported verdict vocabulary

### Phase 3 deliverables

- corrected tensor emission for scalar versus explicit matrix connections
- stable lowering-summary bucket definitions
- reserved metadata schema for advisory-only semantics
- materializer-focused regression tests that inspect weights and metadata together

### Phase 4 deliverables

- IR contract for each currently parser-recognized concept
- planner semantics for each concept on the `nir` backend
- per-concept tests showing one of:
  - executable lowering
  - metadata-only lowering
  - fail-closed rejection

### Phase 5 deliverables

- first-class shape-aware population contract
- first-class structured connectivity contract
- rejection semantics for unsupported tensor operators
- tests for shape validation and structured connectivity downgrade behavior

### Phase 6 deliverables

- end-to-end NIR export tests for the honest current subset
- consumer or converter smoke tests where dependencies exist
- coverage for metadata inspection, not only artifact creation

### Phase 7 deliverables

- export API payloads that include lowering summaries
- Studio export UI that surfaces concept fidelity clearly
- user-visible wording that distinguishes interchange validity from executable parity

## Decision Checkpoints

The following decisions should be made deliberately rather than being left implicit in code.

### Checkpoint 1: Metadata-only permanence

Needed during late Phase 3 or early Phase 4.

Question:

- which currently metadata-only concepts are expected to remain metadata-only for NIR long term,
  and which are intended to gain executable lowering later?

Why it matters:

- this determines whether the current metadata schema is a temporary bridge or part of the stable
  public contract

### Checkpoint 2: Structured connectivity contract

Needed before meaningful Phase 5 work.

Question:

- should structured connectivity be represented in IR primarily as:
  - masks
  - symbolic pattern descriptors
  - explicit sparse index lists
  - some combination of the above

Why it matters:

- the wrong contract here will either overfit one backend or make later tensor lowering harder

### Checkpoint 3: Shape semantics

Needed before convolution or pooling syntax.

Question:

- how should NeuroCNL distinguish:
  - neuron count
  - represented feature dimensions
  - tensor rank and layout
  - channel ordering

Why it matters:

- if these are conflated, shape-aware validation and operator lowering will both be unstable

### Checkpoint 4: NIR operator scope

Needed before promising first-class tensor-native NIR authoring.

Question:

- which NIR operators are actually available and worth targeting directly in this repo's supported
  dependency range?

Why it matters:

- the plan should track the NIR operator surface that can be tested here, not an aspirational one

## Workstream Proposal

The cleanest implementation path is to treat this as four workstreams that converge in Phase 5.

### Workstream A: Export honesty

Owns:

- concept verdicts
- fail-closed rejection
- support matrix sync
- exporter response fields

Stops being the critical path after:

- Phase 2 is complete and stable

### Workstream B: Materializer semantics

Owns:

- connection classification
- tensor emission truthfulness
- metadata schema
- delay or timing lowering experiments

Stops being the critical path after:

- Phase 3 acceptance criteria are met

### Workstream C: IR contract expansion

Owns:

- parser-to-IR semantics for already-recognized concepts
- long-term policy decisions for metadata-only concepts
- shape and structured-connectivity IR design

Stops being the critical path after:

- Phase 4 is stable enough to start Phase 5 without ambiguity

### Workstream D: Product surfacing and consumer safety

Owns:

- API payload shape
- Studio fidelity messaging
- downstream consumer smoke checks

Stops being the critical path after:

- mixed-fidelity NIR graphs are represented consistently across docs, APIs, and UI

## Exit Criteria For Array Work

Phase 5 should not be treated as started in earnest until all of the following are true:

- no parser-recognized NIR concept is silently dropped
- materializer summaries reflect emitted graph structure with stable bucket definitions
- at least one metadata-only concept has an explicit long-term contract decision
- shape semantics are defined in IR terms rather than deferred to parser syntax
- tests verify graph metadata as part of the supported contract

If these conditions are not met, array work is likely to produce attractive syntax on top of an
unreliable semantic base.

## Risk Register

The risks below are the ones most likely to produce misleading success signals.

### Risk 1: Honest metadata on top of dishonest tensors

Failure mode:

- the lowering summary says a connection is approximate or structured, but the emitted tensor still
  looks like an ordinary dense projection with no machine-checkable distinction

Why it matters:

- downstream tools or reviewers may trust the executable graph more than the warning metadata

Mitigation:

- make connection classification visible in both tensor emission behavior and graph metadata
- add tests that inspect emitted weight shapes and values, not just warning strings

### Risk 2: Parser surface outruns export policy

Failure mode:

- new parser-recognized concepts are accepted before NIR export has a documented verdict for them

Why it matters:

- this recreates the exact ambiguity the current honesty work is trying to eliminate

Mitigation:

- require every new parser concept to ship with a `nir` verdict, planner behavior, and tests in the
  same change

### Risk 3: Metadata schema churn breaks consumers

Failure mode:

- metadata keys or summary structure change repeatedly while downstream converters begin depending on
  them

Why it matters:

- the repo gains internal detail but loses cross-module stability

Mitigation:

- reserve a versioned metadata shape
- treat `nir_lowering_summary` as a contract surface once it is exposed through APIs

### Risk 4: Shape semantics become parser-defined instead of IR-defined

Failure mode:

- shape behavior emerges from ad hoc parsing choices rather than a stable IR contract

Why it matters:

- every later tensor operator will inherit that ambiguity

Mitigation:

- define shape in `PopulationIR` first
- make parser syntax a frontend to that contract, not the source of truth

### Risk 5: UI success states overclaim executability

Failure mode:

- Studio or export APIs imply that a successful NIR export means faithful runtime semantics

Why it matters:

- users will treat interchange validity as execution validation

Mitigation:

- expose per-concept fidelity explicitly
- reserve stronger success wording for cases where semantics are actually executable

## Proposed Backlog Order

If this work is resumed as implementation tickets, the safest order is:

1. Finish Slice B from this document.
2. Finish Slice A from this document.
3. Add stable tests for `nir_lowering_summary` metadata shape and versioning.
4. Make one metadata-only permanence decision from Slice C.
5. Define the `PopulationIR.shape` contract without adding new grammar.
6. Define structured-connectivity IR options and choose one primary representation.
7. Only then draft parser syntax for shape-aware populations and structured connectivity.

Why this order:

- it retires semantic ambiguity before adding expressive power
- it keeps documentation and tests ahead of grammar growth
- it reduces the chance that later array syntax has to be redesigned around a moving IR contract

## PR-Sized Task Breakdown

The phases in this document are too large to map directly to reviewable pull requests. The more
practical unit is a contract-complete PR that changes one slice of behavior and its surrounding
docs and tests together.

### PR 1: Finish fail-closed coverage for currently unsupported concepts

Maps to:

- Phase 2
- Slice B

Scope:

- add negative tests for `lateral_inhibition`, `spatial_connectivity`,
  `short_term_plasticity`, `homeostatic_plasticity`, and `neuromodulation`
- ensure `ensure_nir_exportable()` rejects each one with concept-specific messages
- verify planner and docs still report the same unsupported story

Files likely touched:

- `neurocnl/neurocnl/export/test_nir_integration.py`
- `neurocnl/neurocnl/export/nir_exporter.py`
- `neurocnl/neurocnl/test_planner.py`
- `neurocnl/docs/support_matrix.md`

Done when:

- every currently `not_lowered` parser-recognized concept has an automated fail-closed test

### PR 2: Make the materializer truthful for explicit dense matrices

Maps to:

- Phase 3
- Slice A

Scope:

- preserve explicit dense matrix weights in `ConnectionIR` when they already match target shape
- classify connection lowering into stable buckets
- expose the chosen representation through graph metadata and lowering summaries
- add regression tests for:
  - scalar broadcast
  - explicit dense matrix
  - heuristic resize
  - structured-intent metadata-only fallback

Files likely touched:

- `neurocnl/neurocnl/ir/materializer.py`
- `neurocnl/neurocnl/ir/test_materializer.py`
- `neurocnl/neurocnl/export/test_nir_integration.py`

Done when:

- emitted tensors and summary buckets tell the same story for the covered connection types

### PR 3: Stabilize the lowering-summary metadata contract

Maps to:

- late Phase 3
- Phase 6

Scope:

- lock down the summary schema and versioning expectations
- add tests that inspect `nir_lowering_summary` as contract data rather than incidental metadata
- decide whether additional per-connection fields belong in graph metadata or only in node metadata

Files likely touched:

- `neurocnl/neurocnl/ir/materializer.py`
- `neurocnl/neurocnl/ir/test_materializer.py`
- `neurocnl/backend/app/routers/export.py`
- `neurocnl/docs/support_matrix.md`

Done when:

- downstream code can depend on the summary shape without parsing unstable ad hoc metadata

### PR 4: Make one metadata-only concept decision permanent

Maps to:

- Slice C
- Phase 4

Scope:

- choose one of:
  - `population_coding_range`
  - `adaptive_spiking`
  - `receptor_dynamics`
  - `background_noise`
- decide whether it remains metadata-only or gets a future executable-lowering roadmap
- encode the decision in docs, planner semantics, and tests

Files likely touched:

- `neurocnl/neurocnl/backends/capabilities.py`
- `neurocnl/neurocnl/export/nir_exporter.py`
- `neurocnl/neurocnl/test_planner.py`
- `neurocnl/docs/support_matrix.md`
- this plan document

Done when:

- the chosen concept has a stable public story instead of sitting in an open-ended approximation bucket

### PR 5: Define shape in IR before adding shape grammar

Maps to:

- early Phase 5

Scope:

- extend `PopulationIR` with a first-class shape contract
- define validation semantics for `size`, `dimensions`, and `shape`
- add IR and validation tests before adding user-facing sentence forms

Files likely touched:

- `neurocnl/neurocnl/ir/types.py`
- `neurocnl/neurocnl/ir/`
- `neurocnl/neurocnl/layers/`
- new tests under `neurocnl/neurocnl/ir/` and `neurocnl/neurocnl/layers/`

Done when:

- shape semantics are enforced in IR and validation without relying on parser-specific behavior

### PR 6: Define structured-connectivity IR

Maps to:

- Phase 5

Scope:

- choose the primary structured-connectivity representation
- represent one-to-one and at least one explicit sparse form in IR
- define downgrade and rejection behavior for NIR materialization

Files likely touched:

- `neurocnl/neurocnl/ir/types.py`
- `neurocnl/neurocnl/ir/materializer.py`
- `neurocnl/neurocnl/export/nir_exporter.py`
- tests for IR, materializer, and planner behavior

Done when:

- structured connectivity has a stable IR contract even if executable lowering remains partial

## Parallelization Notes

Some work can happen in parallel, but not all of it.

Safe to parallelize:

- Phase 2 fail-closed tests and support-matrix wording updates
- Phase 7 API/UI surfacing drafts, as long as they target existing verdict vocabulary
- consumer smoke-test scaffolding for already-exported metadata

Should stay serialized:

- `PopulationIR.shape` contract design before convolution or pooling syntax
- structured-connectivity IR design before materializer support claims
- metadata schema stabilization before broad downstream consumption

Reason:

- these serialized steps define contracts that other workstreams will depend on

## Done Definition Per Change

Any implementation PR derived from this plan should be considered incomplete unless it includes all
of the following for the touched NIR behavior:

- code changes
- capability or planner updates if the verdict surface changed
- support-matrix or plan updates if the user-visible claim changed
- regression tests for both success and failure paths where relevant

For behavior that changes export payloads or lowering summaries, "done" also requires:

- API surface review in `backend/app/routers/export.py`
- confirmation that metadata keys are either unchanged or intentionally versioned

This repo has repeatedly paid the cost of partial semantic updates. The plan should be executed in
contract-complete slices, not in isolated code-only slices.

## Recommended Execution Order

1. Capability alignment for current NIR export
2. Lowering/export honesty for parser-recognized concepts
3. Materializer improvements for the current semantic subset
4. Expansion of already-parsed concepts into first-class IR/NIR semantics
5. Tensor-native array syntax and IR
6. Round-trip and consumer validation
7. UI and API surfacing

## Bottom Line

The repo no longer needs a proposal for whether NeuroCNL should support NIR at all. It already does. The correct next step is to make current NIR export explicit about what is executable, what is metadata-only, and what must fail closed, then use that honest bridge as the base for later tensor-native array work.

## What To Test

If you want to test the current state after this planning pass, focus on these checks:

1. Direct pipeline smoke:
   - `cd /NeuroMorphicToolKit/neurocnl && PYTHONPATH=. python3 -m pytest neurocnl/export/test_nir_integration.py`
2. Materializer and exporter behavior:
   - `cd /NeuroMorphicToolKit/neurocnl && PYTHONPATH=. python3 -m pytest neurocnl/export -k nir`
3. Planner and capability truthfulness:
   - `cd /NeuroMorphicToolKit/neurocnl && PYTHONPATH=. python3 -m pytest neurocnl -k "planner and nir"`
4. Module quality gates for doc-adjacent NIR work:
   - `cd /NeuroMorphicToolKit/neurocnl && PYTHONPATH=. ruff check .`
   - `cd /NeuroMorphicToolKit/neurocnl && PYTHONPATH=. mypy .`

Manual behavior worth checking:

- export a simple feed-forward CNL spec to NIR and confirm the graph contains `Input`, `LIF`, `Linear`, and `Output`
- export an inhibitory connection and confirm the `nir.Linear.weight` values are signed negative
- export a spec with delay or STDP and confirm those semantics appear in metadata, not as executable NIR nodes
- export a branching topology and confirm it still lowers, but only through dense `Linear` projections
- try a parser-recognized concept such as `spatial_connectivity` or `background_noise` and check whether the result is currently lowered, approximated, metadata-only, or silently dropped

If you want one highest-signal manual test, use a CNL spec with:

- one input population
- one hidden LIF population
- one output population
- one inhibitory edge
- one delayed edge
- one STDP declaration

That single spec exercises the current honest subset plus the main metadata-only gaps this plan is targeting next.

The old version of this plan was right about the long-term direction:

- CNL does not yet express the full tensor-native power of NIR
- the materializer still overuses dense matrix fallback
- richer shape, sparse, and convolution semantics are still missing

But the old version was wrong about the starting point.

NeuroCNL already has a direct NIR export bridge. The correct next step is to make that bridge honest and semantically clear before extending the language into full array- and tensor-native NIR authoring.
