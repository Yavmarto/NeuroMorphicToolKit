# NIR and CNL Capability Analysis and Bridge Plan

## Scope

This note analyzes the current bridge between NeuroCNL (`cnl`) and NIR inside this repo and proposes an implementation plan to close the remaining gaps.

Primary sources inspected:

- `neurocnl/neurocnl/cnl/cnl_parser.py`
- `neurocnl/neurocnl/cnl/cnl_grammar.md`
- `neurocnl/neurocnl/ir/lowering.py`
- `neurocnl/neurocnl/ir/materializer.py`
- `neurocnl/neurocnl/export/nir_exporter.py`
- `neurocnl/neurocnl/pipeline.py`
- `neurocnl/neurocnl/backends/capabilities.py`
- `neurocnl/docs/support_matrix.md`
- `neurocnl/neurocnl/export/test_nir_integration.py`

## Current CNL Capabilities

### What CNL does well today

- CNL has a broad parser surface. The grammar document enumerates thresholding, refractory behavior, membrane decay, synaptic weight, delay, STDP, inhibitory links, population coding, topology, timing declarations, Akida declarations, and several more advanced neuro concepts.
- Multi-line parsing is already normalized through `parse_spec_text()` in `neurocnl/neurocnl/pipeline.py`.
- There is a typed semantic IR boundary. `lower_to_ir()` converts parsed sentences into `NetworkIR`, `PopulationIR`, `ConnectionIR`, `LearningRuleIR`, and timing declarations.
- CNL can already compile directly to NIR without going through Nengo. `compile_to_nir()` lowers parsed specs to IR and calls `export_to_nir()`.

### Where CNL stops today

- The parser surface is significantly wider than the lowering surface.
- `neurocnl/neurocnl/ir/lowering.py` only advertises lowering support for:
  - `threshold_firing`
  - `refractory_period`
  - `membrane_potential_decay`
  - `synaptic_weight`
  - `axonal_delay`
  - `stdp_learning`
  - `inhibitory_connection`
  - `population_coding`
  - `network_topology`
  - `timing_declaration`
  - `akida_hardware`
  - `akida_spatiotemporal`
- Several parser-recognized concepts are therefore not part of the CNL->IR->NIR bridge yet, including:
  - `lateral_inhibition`
  - `homeostatic_plasticity`
  - `neuromodulation`
  - `population_coding_range`
  - `adaptive_spiking`
  - `receptor_dynamics`
  - `short_term_plasticity`
  - `background_noise`
  - `spatial_connectivity`
- There is also doc drift: `cnl_grammar.md` says the parser recognizes 19 concepts, but the table currently lists more than that.

## Current NIR Capabilities

### What the NIR path does well today

- NIR export is no longer Nengo-dependent for the core path.
- `Materializer.materialize()` converts `NetworkIR` into a `nir.NIRGraph`.
- Population roles are mapped cleanly:
  - `role="input"` -> `nir.Input`
  - `role="output"` -> `nir.Output`
  - otherwise -> `nir.LIF`
- Connections are materialized as explicit `nir.Linear` nodes with deterministic dense weight matrices.
- Provenance and extra semantics are preserved as metadata on nodes and edges.
- STDP and unscoped learning rules are preserved as metadata.
- Integration coverage exists for the direct CNL->IR->NIR path in `neurocnl/neurocnl/export/test_nir_integration.py`.

### Where the NIR path stops today

- NIR is treated as an export format, not an executable backend inside NeuroCNL.
- `neurocnl/docs/support_matrix.md` calls `nir` faithful, but `nir` is not present in `neurocnl/neurocnl/backends/capabilities.py`, so planner-backed capability reporting does not currently own that claim.
- The materializer is semantically narrow:
  - connections become full dense matrices filled from a scalar weight
  - delays are preserved in metadata, not as active NIR delay semantics
  - learning rules are preserved in metadata, not executable graph behavior
  - refractory period is preserved in metadata on `nir.LIF`, not an explicit separate dynamic
  - advanced plasticity, noise, receptor, and spatial semantics are not represented as NIR nodes
- The bridge is therefore structurally valid for simple feedforward LIF graphs, but not semantically complete for the full parser surface.

## Gap Summary

The gap is not "CNL cannot export to NIR." That part already exists.

The real gap is that the current bridge only covers a relatively small semantic subset faithfully:

1. Parser breadth is larger than IR lowering breadth.
2. IR lowering breadth is larger than materialized NIR semantics.
3. Capability docs claim more alignment than the planner and backend registry currently encode.
4. Fidelity is preserved mostly as metadata once the design leaves the core LIF-plus-dense-weights subset.

## Recommended Bridge Strategy

### Phase 1: Make the contract honest

Goal: eliminate ambiguity before expanding functionality.

Work:

- Add an explicit `nir` capability profile to `neurocnl/neurocnl/backends/capabilities.py`.
- Decide whether `nir` should be classified as:
  - `faithful` for the currently supported IR subset only, or
  - `approximate` until delay, learning, and advanced dynamics have first-class representation.
- Align `neurocnl/docs/support_matrix.md`, planner output, and export headers with the same claim.
- Fix the concept-count drift in `neurocnl/neurocnl/cnl/cnl_grammar.md`.
- Document the exact "CNL subset that round-trips to NIR without semantic loss".

Why first:

- The repo currently has a source-of-truth mismatch between docs and capability code.
- Expanding functionality before fixing claims will make downstream consumers trust the wrong fidelity signals.

### Phase 2: Separate supported, metadata-only, and unsupported concepts

Goal: make lowering outcomes explicit instead of silently partial.

Work:

- Introduce concept-level lowering verdicts:
  - `lowered_faithfully`
  - `lowered_as_metadata`
  - `not_lowered`
- Extend `NetworkIR` or lowering results to carry those verdicts.
- For each parser-recognized concept, declare one of:
  - first-class IR concept
  - metadata-only annotation
  - rejected for NIR export
- Fail closed when a user requests NIR export for a concept that is parser-recognized but neither lowered nor intentionally downgraded.

Files likely touched:

- `neurocnl/neurocnl/ir/types.py`
- `neurocnl/neurocnl/ir/lowering.py`
- `neurocnl/neurocnl/planner.py`
- `neurocnl/backend/app/routers/export.py`

Why this matters:

- Today the parser can accept concepts that the NIR bridge does not actually carry through.
- That is the highest-risk source of user misunderstanding.

### Phase 3: Expand the semantic IR to cover the missing concepts intentionally

Goal: close the parser->IR gap.

Recommended order:

1. `population_coding_range`
2. `background_noise`
3. `spatial_connectivity`
4. `lateral_inhibition`
5. `adaptive_spiking`
6. `receptor_dynamics`
7. `short_term_plasticity`
8. `homeostatic_plasticity`
9. `neuromodulation`

Rationale:

- The first group mainly affects topology, parameterization, or annotations.
- The later group needs new dynamics or control channels and is harder to encode honestly in NIR.

Design rule:

- Do not add parser support from memory.
- For each concept added to lowering, define:
  - the IR fields
  - planner semantics
  - NIR encoding strategy
  - tests proving either faithful or approximate preservation

### Phase 4: Upgrade the materializer from "dense LIF scaffolding" to "semantic NIR lowering"

Goal: close the IR->NIR gap.

Work:

- Replace metadata-only delay handling with actual NIR delay nodes where possible.
- Distinguish scalar broadcast weights from true dense connectivity.
- Preserve sparse or local connectivity instead of converting every projection into a full dense matrix.
- Encode inhibitory and receptor semantics with explicit node patterns where NIR supports them; otherwise downgrade them explicitly.
- Preserve timing declarations in a machine-checked way, not just as incidental metadata.
- Define how learning rules should be represented:
  - native NIR node semantics if available
  - otherwise standardized metadata schema plus planner downgrade

Files likely touched:

- `neurocnl/neurocnl/ir/materializer.py`
- `neurocnl/neurocnl/export/nir_exporter.py`
- any NIR converter backends that consume the produced graph

Success criterion:

- A reviewer should be able to inspect a generated `nir.NIRGraph` and determine which semantics are executable versus advisory.

### Phase 5: Add round-trip and consumer validation

Goal: prove the bridge works for real downstream use.

Work:

- Add golden tests for representative CNL families:
  - simple feedforward
  - inhibitory projection
  - delay
  - STDP metadata
  - branching topology
  - input/output populations
- Add negative tests for concepts that must currently reject NIR export.
- Add round-trip tests where practical:
  - CNL -> IR -> NIR
  - NIR -> consumer conversion path
  - resulting consumer artifact preserves the intended subset
- Add planner tests asserting truthful verdicts for NIR exports.

Priority test files:

- `neurocnl/neurocnl/export/test_nir_integration.py`
- new `neurocnl/neurocnl/ir/test_materializer.py`
- planner capability tests under `neurocnl/neurocnl/tests/`

### Phase 6: Surface fidelity in the product UX

Goal: make export limitations visible to operators.

Work:

- Return per-concept fidelity annotations from the backend export routes.
- Show "faithful", "metadata-only", and "unsupported" markers in the Studio export UI.
- Make NIR export warnings actionable, not generic.

Why:

- Users need to know whether a `.nir` artifact is a faithful computational graph or just a structurally compatible container with advisory metadata.

## Concrete Deliverables

Recommended implementation slices:

1. Capability alignment slice
   - add `nir` backend profile
   - align support matrix and planner verdicts
   - fix grammar doc drift

2. Lowering honesty slice
   - add lowering verdict metadata
   - reject parser-only concepts during NIR export

3. Materializer semantics slice
   - implement explicit delay lowering
   - standardize metadata schema for non-executable concepts

4. Missing-concepts slice
   - add one concept family at a time from parser to IR to NIR

5. UX and API slice
   - expose fidelity annotations in export responses and frontend labels

## Recommended Order of Execution

1. Fix capability truthfulness first.
2. Make partial lowering explicit second.
3. Improve NIR semantic lowering for already-supported concepts third.
4. Expand parser-recognized concepts into IR and NIR one family at a time.
5. Expose fidelity annotations in API and UI last, once the backend semantics are stable.

## Bottom Line

The bridge from CNL to NIR already exists and is useful today for simple population-and-connection graphs.

What is missing is not the file export itself, but a trustworthy semantic contract:

- which CNL concepts truly survive into NIR,
- which survive only as metadata,
- which must reject export,
- and how those verdicts are communicated consistently in code, tests, docs, and UI.
