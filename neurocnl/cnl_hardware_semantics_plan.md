# CNL Hardware Semantics And Backend Realism Plan

This plan turns the current critique of NeuroCNL into concrete implementation work for this repository.

The key conclusion is:

NeuroCNL already has a broad and useful language surface, but its next major step should be improving semantic fidelity, backend capability modeling, and hardware-aware validation rather than only adding more grammar.

This document uses the following terms consistently:

- `parser-recognized`: accepted by the CNL parser
- `faithful`: execution closely preserves intended semantics
- `approximate`: execution or export works with heuristics or backend-specific simplifications
- `unsupported`: runtime or backend support cannot yet be honestly claimed

## Current Read

The repository already supports a wider CNL than the critique assumed:

- Parser support extends beyond the original reflex-arc concepts into adaptive spiking, receptor dynamics, short-term plasticity, background noise, and spatial connectivity.
- The pipeline already supports simulation `dt` at runtime.
- There are exporter and contract layers for Loihi, Lava, SpiNNaker, and embedded targets.
- Backend fidelity still varies by target; exporter presence should be treated as a portability layer, not as proof of production-ready deployment.

The main gap is that these capabilities are not yet unified by a strong intermediate representation and backend-specific semantic checks.

## Strategic Goal

Evolve NeuroCNL from:

`CNL -> parser -> Nengo-centric generation -> exporter stubs`

toward:

`CNL -> typed IR -> validator -> backend capability planner -> simulator/exporter/compiler`

This keeps NeuroCNL strongest where it is already differentiated:

- readable specification
- interdisciplinary communication
- rapid prototyping
- portable frontend for multiple neuromorphic backends

## Guiding Principles

1. Treat CNL as a specification language first, not a direct hardware language.
2. Make unsupported backend behavior explicit instead of silently approximating it.
3. Promote time, quantization, and hardware limits to first-class concepts.
4. Separate parser coverage from execution fidelity in docs, tests, and APIs.
5. Prefer backend capability reports over optimistic export success.

## Workstreams

## Workstream 1: Introduce A Typed Intermediate Representation

### Why

Right now the parser returns concept-tagged dictionaries and the generator infers behavior directly from them. That makes it hard to:

- reason about per-backend support
- preserve provenance cleanly
- distinguish declarative intent from Nengo-specific approximations
- attach hardware constraints and time semantics

### Deliverables

- A typed IR package, likely `neurocnl/ir/`
- IR nodes for:
  - populations
  - neuron models
  - connections
  - synapse dynamics
  - learning rules
  - timing declarations
  - hardware hints
  - backend requirements
- A lowering step from parsed sentences to IR
- Provenance preserved from original source lines into IR nodes

### Suggested Files

- `neurocnl/ir/__init__.py`
- `neurocnl/ir/types.py`
- `neurocnl/ir/lowering.py`
- `neurocnl/ir/test_ir_lowering.py`
- `neurocnl/pipeline.py`

### Implementation Notes

- Keep the existing parser API stable at first.
- Add a new pipeline stage: `parse -> lower_to_ir -> validate_ir -> generate/export`.
- Let the IR encode intent like "homeostatic target rate" without forcing an immediate Nengo interpretation.

## Workstream 2: Make Time A First-Class Part Of The Language

### Why

The critique is correct that temporal semantics are under-specified relative to real neuromorphic systems. Simulation uses `dt`, but the language does not yet declare timing assumptions directly.

### Deliverables

- CNL support for global timing declarations
- IR fields for:
  - `dt`
  - delay quantization
  - learning window quantization
  - biological vs accelerated timescale
  - backend clock assumptions
- Validation that converts continuous-looking statements into explicit discrete timing semantics

### Example Future CNL

```text
The network MUST operate WITH timestep of 1 ms
The network MUST use discrete delays quantized to 1 ms
The network MUST run AT 1000x biological speed
```

### Suggested Files

- `neurocnl/cnl/cnl_parser.py`
- `neurocnl/cnl/cnl_grammar.md`
- `neurocnl/contracts/neuron_params.py`
- `neurocnl/ir/types.py`
- `neurocnl/layers/layer1_invariants.py`
- `neurocnl/layers/layer1_validator.py`
- `backend/app/schemas/simulate.py`

### Implementation Notes

- Distinguish simulation time resolution from biological interpretation.
- Delays should validate against both abstract correctness and backend resolution.
- Backend validation should report when a timing declaration must be rounded or clipped.

## Workstream 3: Build Backend Capability Profiles

### Why

Today the repo can export to multiple targets, but it does not fully express what each backend can actually honor. This is where many silent mismatches can happen.

### Deliverables

- Capability profiles for:
  - `nengo`
  - `loihi`
  - `lava`
  - `spinnaker`
  - `teensy`
- Per-backend declarations for:
  - supported neuron models
  - supported learning rules
  - supported synapse models
  - delay resolution and limits
  - quantization rules
  - population size/core limits
  - sparse connectivity support
  - stochastic support
- A capability checker that produces:
  - `faithful`
  - `approximate`
  - `unsupported`

### Suggested Files

- `neurocnl/backends/__init__.py`
- `neurocnl/backends/capabilities.py`
- `neurocnl/backends/test_capabilities.py`
- `neurocnl/export/__init__.py`
- `backend/app/services/hardware_service.py`

### Implementation Notes

- Return structured reasons, not just boolean pass/fail.
- Add API output that tells the user whether a spec is faithfully supported on a requested backend.
- Make exporter success contingent on capability review, or at least include warnings in the result.

## Workstream 4: Strengthen Hardware Constraint Modeling

### Why

The current Loihi checks are a good start, but they are still thin. Real hardware mapping depends on more than weight range and ensemble size.

### Deliverables

- Extended hardware contracts for:
  - fan-in / fan-out
  - compartment/core budget
  - routing pressure estimates
  - weight precision and quantization mode
  - delay bucket limits
  - learning rule availability
  - memory estimates
  - energy estimates where feasible
- Hardware-specific constraint reports with severity levels:
  - error
  - warning
  - approximation notice

### Suggested Files

- `neurocnl/contracts/hardware_export.py`
- `neurocnl/layers/layer1_invariants.py`
- `neurocnl/layers/layer1_validator.py`
- `backend/app/services/energy_service.py`
- `backend/tests/test_hardware_service.py`

### Implementation Notes

- Start with Loihi because there is already a contract path.
- Represent "unknown" explicitly when the repo cannot yet estimate a hardware constraint.
- Avoid fake precision; it is better to say "not modeled" than to imply deployment certainty.

## Workstream 5: Separate Declarative Support From Approximate Nengo Realizations

### Why

Some newer concepts are already parseable, but their generated behavior is only a loose approximation. That is useful for prototyping, but it should be labeled honestly.

### Deliverables

- A per-concept execution fidelity table
- Generator annotations marking concept realizations as:
  - direct mapping
  - heuristic approximation
  - placeholder
- Test expectations based on fidelity level

### Suggested Files

- `neurocnl/generation/nengo_generator.py`
- `neurocnl/generation/test_nengo_generator.py`
- `docs/api/generation.md`
- `README.md`

### Immediate Candidates

- Homeostatic plasticity
- Neuromodulation
- Spatial connectivity
- Short-term plasticity

### Implementation Notes

- The first pass does not need to remove approximations.
- It should make them visible in return metadata and docs.
- Then improve them concept by concept once the IR and capability layer exist.

## Workstream 6: Add A Backend Planning Stage

### Why

Users need a result that answers:

- Can this spec run on backend X?
- If yes, is it faithful or approximate?
- What changes would make it deployable?

### Deliverables

- A planner stage that consumes IR plus a backend target and returns:
  - support verdict
  - downgraded features
  - required rewrites
  - quantization / timing adjustments
  - partitioning warnings

### Suggested Files

- `neurocnl/planner.py`
- `neurocnl/test_planner.py`
- `backend/app/routers/validate.py`
- `backend/app/schemas/common.py`

### Example Output Shape

```json
{
  "backend": "loihi",
  "verdict": "approximate",
  "supported": ["threshold_firing", "refractory_period", "axonal_delay"],
  "approximated": ["homeostatic_plasticity"],
  "unsupported": ["stochastic_spiking"],
  "warnings": ["Delay 3.5 ms rounded to 4 ms at target timestep."]
}
```

## Workstream 7: Expand Grammar Only Where The Backend Story Is Credible

### Why

Adding syntax is easy; supporting it honestly is the hard part.

### Priority Order

1. Stochastic / probabilistic spiking
2. Reservoir / liquid-state modules
3. Sparse event-routing and connectivity policies
4. Multi-compartment or dendrite-aware neurons
5. Glial / astrocytic modulation

### Rule

No new concept should ship without:

- parser coverage
- IR representation
- Layer 1 or backend validation story
- generator/export behavior classification
- tests
- docs that state backend fidelity

## Workstream 8: Clean Up Documentation And Positioning

### Why

The current docs and README understate some implemented features while also oversimplifying backend realism.

### Deliverables

- Update README concept count and capability messaging
- Add a "backend fidelity" section
- Add a "what is simulation-faithful vs export-only" section
- Add a "hardware access requirements" section

### Suggested Files

- `README.md`
- `docs/index.md`
- `docs/api/cnl.md`
- `docs/api/export.md`
- `docs/DEPLOYMENT_GUIDE.md`

## Phased Roadmap

## Phase 0: Documentation And Terminology Reset

### Goal

Align public docs with the actual repo and stop overselling exporter maturity.

### Tasks

- Update README concept count and examples
- Document current approximations
- Add backend fidelity terminology

### Estimated Difficulty

Low

## Phase 1: IR Foundation

### Goal

Introduce a typed IR without breaking the existing public API.

### Tasks

- Create IR types
- Lower parsed sentences into IR
- Preserve line provenance
- Add tests

### Estimated Difficulty

Medium

## Phase 2: Time Semantics And Capability Profiles

### Goal

Make time and backend support explicit.

### Tasks

- Add timing declarations to grammar
- Add backend capability registry
- Add planner results
- Thread planner output through API responses

### Estimated Difficulty

Medium to high

## Phase 3: Hardware Constraint Expansion

### Goal

Increase confidence in backend-specific validation.

### Tasks

- Extend Loihi constraints first
- Add SpiNNaker and Teensy constraint reports
- Add quantization and routing warnings

### Estimated Difficulty

High

## Phase 4: Semantic Fidelity Pass

### Goal

Replace current heuristics and placeholders with better realizations where feasible.

### Tasks

- Improve homeostasis semantics
- Improve neuromodulation semantics
- Review STP and spatial connectivity
- Mark irreducible approximations explicitly

### Estimated Difficulty

High

## Phase 5: Frontier Grammar Expansion

### Goal

Expand the language only after the semantic and backend foundation is solid.

### Tasks

- Add stochastic concepts
- Add reservoir modules
- Add multi-compartment abstractions

### Estimated Difficulty

Very high

## Testing Strategy

Each phase should add tests at three levels:

- parser and IR unit tests
- backend capability and validation tests
- end-to-end pipeline tests with explicit expected fidelity classifications

The most important new test category is:

"This parses successfully, but backend X must report `approximate` or `unsupported`."

That is the key protection against silent overclaiming.

## What Can Be Done Without Hardware Vendor Program Access

Most of this roadmap is still possible without access to hardware developer programs.

### Feasible Without Access

- IR design and lowering
- timing semantics in the language
- backend capability registry
- capability/planner APIs
- improved docs and user-facing warnings
- contract and invariant expansion
- Nengo-side semantic upgrades
- export generation improvements
- simulation-based validation
- approximate quantization analysis
- offline tests against public docs and emulator behavior

### In Practice

Roughly 70-85% of the engineering roadmap is still achievable without direct vendor access because the biggest missing pieces are semantic architecture and honesty around support, not raw hardware execution.

## What Likely Requires Developer Program Or Hardware Access

These areas either require direct access or become much more credible with it:

- validating real Loihi deployment artifacts on actual hardware
- measuring real routing failures and partitioning behavior
- checking energy and latency numbers against device reality
- confirming support for specific on-chip learning modes
- understanding undocumented or version-sensitive deployment constraints
- testing backend behavior against true compiler toolchains rather than simplified exporters
- building a trustworthy cross-hardware equivalence benchmark suite

### Practical Estimate

Only about 15-30% of the roadmap strictly requires direct access, but it is the most credibility-critical 15-30%.

## What Would Likely Become Possible With Access

If the project gained access to vendor programs, developer portals, emulator stacks, or physical devices, the following would become much more realistic:

1. Real backend certification:
   NeuroCNL could say not just that it exports, but that a given spec has been validated on real hardware.

2. More accurate capability profiles:
   You could replace many conservative assumptions with measured backend facts.

3. Partitioning-aware compilation:
   The planner could evolve from simple limit checks into real placement and routing guidance.

4. Hardware-grounded cost models:
   Energy, memory, and latency estimates could move from rough heuristics to benchmark-backed predictions.

5. Cross-hardware behavioral validation:
   The same IR could be run on CPU simulation, emulator, and hardware with tolerance-based comparisons.

6. Better support for hardware-specific learning:
   Some features are not meaningfully modellable without access to the actual programming stack and constraints.

## Recommended Order For This Repo

If the goal is to make NeuroCNL meaningfully stronger in the near term, the highest-leverage order is:

1. Fix docs and expose current fidelity limits.
2. Add IR and provenance-preserving lowering.
3. Add backend capability profiles and planner output.
4. Add timing declarations and quantized timing validation.
5. Expand Loihi constraints first, then other backends.
6. Improve semantics of existing advanced concepts before adding new ones.
7. Pursue vendor-program-backed validation when access becomes available.

## Definition Of Success

This plan succeeds when NeuroCNL can honestly say:

- what a spec means
- what backend features it depends on
- which parts of that meaning are preserved on each target
- what is only approximate
- what cannot yet be deployed faithfully

That would move the project much closer to a credible frontend specification layer for neuromorphic toolchains, even before full hardware access exists.
