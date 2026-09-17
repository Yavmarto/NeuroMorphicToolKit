# NeuroCNL Explained — Current Parser, IR, Validation, and Generation

This document describes how NeuroCNL works today in code, not how it was
originally envisioned. It was checked against the current implementation in:

- `neurocnl/cnl/cnl_parser.py`
- `neurocnl/cnl/cnl_grammar.md`
- `neurocnl/ir/types.py`
- `neurocnl/ir/lowering.py`
- `neurocnl/planner.py`
- `neurocnl/pipeline.py`
- `neurocnl/layers/layer1_validator.py`
- `neurocnl/layers/layer1_invariants.py`
- `neurocnl/layers/layer2_validator.py`
- `neurocnl/generation/nengo_generator.py`
- `backend/app/services/neurocnl_bridge.py`
- `backend/app/routers/parse.py`
- `backend/app/routers/validate.py`
- `backend/app/routers/simulate.py`

## What NeuroCNL Does

NeuroCNL is a regex-based Controlled Natural Language for describing
neuromorphic circuits and related backend constraints. A multi-line spec is:

1. Parsed line by line into structured sentence dictionaries.
2. Lowered into an internal IR (`NetworkIR`) for all 21 supported concepts.
3. Reduced into a smaller validation-parameter dictionary (legacy validation path).
4. Validated with Layer 1 physical checks and Layer 2 cross-sentence checks.
5. Planned against a backend capability registry as `faithful`,
   `approximate`, or `unsupported`.
6. **Compiled to a `nir.NIRGraph`** via `Materializer().materialize()`. No
   Nengo network is constructed in this path.
7. Optionally written to a `.nir` file with `nir.write()`.
8. Optionally checked with generated Layer 3 pytest assertions.

There is no LLM-based parsing in this path.

## 1. Parsing

### Main Files

- `neurocnl/cnl/cnl_parser.py`
- `neurocnl/cnl/types.py`
- `neurocnl/cnl/cnl_grammar.md`
- `neurocnl/pipeline.py`

### Parsed Output Shape

`parse(sentence)` returns a `ParsedSentence` TypedDict with:

- `concept`
- `subject`
- `action`
- `verb`
- `negated`
- `condition`
- `raw`

If a line number is provided, the parsed sentence also includes `line`.

`parse_spec_text(spec_text)` parses each non-empty, non-comment line and returns
per-line parse results with:

- `line`
- `raw`
- `parsed`
- `valid`
- `error`
- `error_detail`

### Parser Coverage

The parser currently recognizes **21 concepts**:

1. `threshold_firing`
2. `refractory_period`
3. `membrane_potential_decay`
4. `synaptic_weight`
5. `axonal_delay`
6. `timing_declaration`
7. `stdp_learning`
8. `inhibitory_connection`
9. `population_coding`
10. `network_topology`
11. `lateral_inhibition`
12. `homeostatic_plasticity`
13. `neuromodulation`
14. `population_coding_range`
15. `adaptive_spiking`
16. `receptor_dynamics`
17. `short_term_plasticity`
18. `background_noise`
19. `spatial_connectivity`
20. `akida_hardware`
21. `akida_spatiotemporal`

Parser recognition does not imply faithful NIR execution. See `cnl_grammar.md`
for sentence patterns and the NIR support matrix (`docs/support_matrix.md`)
for per-concept fidelity verdicts.

### Important Parser Limits

The parser surface is concept-specific rather than fully uniform.

- `threshold_firing` accepts only `sensory neuron`, `motor neuron`,
  `interneuron neuron`, and bare `interneuron`.
- `refractory_period` and `membrane_potential_decay` are narrower and only
  accept sensory/motor neuron forms.
- `synaptic_weight` requires the literal `The connection from ... to ...` form.
- `timing_declaration` supports exactly three strict sentence families.
- Several newer concepts use broader subject matching and therefore feel more
  permissive than the older reflex-arc core concepts.

## 2. IR Lowering

### Main Files

- `neurocnl/ir/types.py`
- `neurocnl/ir/lowering.py`

The parser now feeds an internal typed IR layer before generation. This IR is
backend-agnostic and records provenance on populations, connections, timing
declarations, and learning rules.

### What Lowers Successfully Today

All 21 parser-recognized concepts lower successfully via `lower_to_ir()`. The
`SUPPORTED_CONCEPTS` set in `neurocnl/ir/lowering.py` covers all of them:

**Core (structure-forming)**
1. `threshold_firing` — population `threshold`
2. `refractory_period` — population `refractory_period`
3. `membrane_potential_decay` — population `membrane_time_constant`
4. `synaptic_weight` — connection `weight` (scalar, dense matrix, identity, or diagonal)
5. `axonal_delay` — connection `delay` or global default on `network.metadata`
6. `inhibitory_connection` — connection `polarity = inhibitory`, signed weight
7. `population_coding` — population `size`, `dimensions`, `shape`, `role`
8. `population_coding_range` — population attribute `population_coding_range_degrees`
9. `network_topology` — population declarations + multi-target projections
10. `timing_declaration` — `TimingDeclarationIR` entries on `network.timing_declarations`

**Advanced (lower as attributes or metadata)**
11. `stdp_learning` — `LearningRuleIR` (scoped to connection, or global)
12. `adaptive_spiking` — population attribute `adaptive_spiking_enabled`
13. `receptor_dynamics` — connection attribute `receptor_type`, or `network.metadata["global_receptor_dynamics"]`
14. `background_noise` — population attribute `background_noise_value`
15. `lateral_inhibition` — self-loop connection with `connectivity_pattern = local_radius`
16. `homeostatic_plasticity` — population attribute `homeostatic_target_rate_hz`
17. `neuromodulation` — structured rule in `network.metadata["neuromodulation_rules"]`
18. `short_term_plasticity` — connection attribute `short_term_plasticity_type`, or global rule
19. `spatial_connectivity` — connection `connectivity_pattern` (one_to_one, binary_mask, random_sparsity, distance_dependent_probability, local_radius)

**Akida-specific**
20. `akida_hardware` — `network.akida_hardware` (`AkidaHardwareIR`)
21. `akida_spatiotemporal` — `network.akida_connection_properties` list

If a parsed concept is not in `SUPPORTED_CONCEPTS`, lowering raises `LoweringError`
rather than silently dropping meaning.

### What The IR Captures

`NetworkIR` currently contains:

- `populations`
- `connections`
- `learning_rules`
- `timing_declarations`
- `backend_hints`
- `metadata`

At this stage, the lowering pass is intentionally conservative. It gives the
pipeline a normalized core network view, but it does not yet attempt to encode
every advanced concept the parser can recognize.

## 3. Parameter Extraction

### Main File

- `neurocnl/pipeline.py`

`default_params_with_provenance(parsed_specs)` builds a small
`neuron_params` dictionary plus source provenance. Today it extracts only a
subset of parsed values:

- `threshold`
- `refractory_period`
- `tau`
- `synaptic_weight`
- `axonal_delay`
- `population_n_neurons`

It also seeds defaults such as:

- `resting_potential = 0.0`
- `reset_potential = 0.0`
- `current_voltage = 0.5`

Timing declarations are not routed through this extractor. Instead, Layer 1
validation applies them separately and augments the validation parameter set
with:

- `network_timestep`
- `delay_quantization_step`
- `biological_speed_multiplier`

This is an important implementation detail: the parser recognizes more concepts
than the default parameter extractor reduces into Layer 1 inputs. Many newer
concepts are either lowered into IR only, handled directly in generation, or
tracked as advisory fidelity metadata.

## 4. Validation

Validation runs in two layers via `validate_spec()` in `pipeline.py`.

### Layer 1: Physical, Contract, and Timing Checks

#### Main Files

- `neurocnl/layers/layer1_validator.py`
- `neurocnl/layers/layer1_invariants.py`
- `neurocnl/contracts/neuron_params.py`
- `neurocnl/contracts/hardware_export.py`

#### What Layer 1 Does

`layer1_validator.validate()` currently:

1. Applies timing declarations from parsed specs onto a copied parameter set.
2. Validates that parameter set with `LIFNeuronContract`.
3. When `backend == "loihi"`, also validates with `LoihiExportContract`.
4. Runs the functional invariant registry in `ALL_INVARIANTS`.
5. Adds `LOIHI_INVARIANTS` for the Loihi backend.
6. Produces both hard failures and advisory warnings.

The codebase also defines other contracts, but the Layer 1 entry point is still
centered on the LIF neuron contract plus optional Loihi export constraints.

#### Layer 1 Invariants

`ALL_INVARIANTS` currently contains 26 checks:

1. `threshold_above_resting`
2. `refractory_period_positive`
3. `time_constant_positive`
4. `reset_at_or_below_threshold`
5. `membrane_potential_decays_toward_rest`
6. `axonal_delay_in_range`
7. `stdp_window_positive`
8. `stdp_weight_bounds_valid`
9. `inhibitory_weight_negative`
10. `population_neuron_count_positive`
11. `population_dimensions_positive`
12. `population_radius_positive`
13. `learning_rate_positive`
14. `learning_rule_valid`
15. `network_timestep_positive`
16. `delay_quantization_step_positive`
17. `biological_speed_multiplier_positive`
18. `delay_quantization_not_finer_than_timestep`
19. `lateral_inhibition_radius_positive`
20. `homeostatic_target_rate_positive`
21. `neuromodulation_factor_positive`
22. `population_coding_range_positive`
23. `adaptive_spiking_tau_positive`
24. `stp_recovery_time_positive`
25. `background_noise_variance_positive`
26. `spatial_connectivity_radius_positive`

Loihi adds 4 more hard checks:

1. `loihi_weight_quantizable`
2. `loihi_ensemble_size_within_limits`
3. `loihi_delay_in_range`
4. `loihi_delay_ticks_within_limits`

Layer 1 can also emit Loihi-specific soft warnings such as:

- `loihi_timestep_assumed_default`
- `loihi_timestep_resolution_mismatch`
- `loihi_delay_quantization_mismatch`

These warnings do not fail validation, but they do affect backend-support
reporting later in the pipeline.

#### Layer 1 Return Shape

Layer 1 now returns:

```python
{
    "passed": [...],
    "failed": [{"name": ..., "reason": ..., "code": ...}, ...],
    "warnings": [{"name": ..., "severity": "warning", ...}, ...],
    "overall": bool,
}
```

### Layer 2: Cross-Sentence Checks

#### Main File

- `neurocnl/layers/layer2_validator.py`

`validate_cross_sentence(parsed_specs)` currently runs 9 checks:

1. `no_dangling_connections`
2. `no_contradictory_params`
3. `no_orphan_populations`
4. `no_negative_threshold_without_inhibition`
5. `no_zero_weight_synapses`
6. `no_self_referencing_connections`
7. `no_empty_network`
8. `no_single_node_network`
9. `no_zero_edge_network`

It returns:

```python
{
    "checks_passed": [...],
    "checks_failed": [{"check": ..., "detail": ...}, ...],
    "neurons_found": [...],
    "connections_found": [...],
    "overall": bool,
}
```

## 5. Backend Planning

### Main Files

- `neurocnl/backends/capabilities.py`
- `neurocnl/planner.py`

Once IR lowering succeeds, the pipeline computes an advisory backend-support
plan against capability profiles for:

- `nengo`
- `loihi`
- `lava`
- `spinnaker`
- `teensy`

The planner produces:

- `backend`
- `verdict`
- `supported_concepts`
- `approximated_concepts`
- `unsupported_concepts`
- `warnings`

The overall verdict is:

- `faithful` when all present lowered concepts map cleanly and there are no
  warnings
- `approximate` when concepts are only partially supported or warnings are
  present
- `unsupported` when any present lowered concept is unsupported for the chosen
  backend

This planner is advisory in the current implementation. It does not replace the
existing validation pass.

## 6. Generation (Legacy Nengo Simulation Path)

> **This section describes the `nengo_generator.py` path used by `run_pipeline()`
> for Nengo / Loihi simulation only. The primary supported compile surface is
> `compile_to_nir()` — which produces a `nir.NIRGraph` directly and never
> constructs a Nengo network. If you are using `compile_to_nir()`, skip this
> section.**

### Main File

- `neurocnl/generation/nengo_generator.py`

`generate(parsed_specs, neuron_params)` still depends on four core concepts for
successful network construction:

1. `threshold_firing`
2. `refractory_period`
3. `membrane_potential_decay`
4. `synaptic_weight`

If any of those are missing, generation fails with `GeneratorError`.

After that, the generator scans parsed specs directly and applies additional
features, including:

- `axonal_delay`
- `stdp_learning`
- `inhibitory_connection`
- `population_coding`
- `network_topology`
- `lateral_inhibition`
- `homeostatic_plasticity`
- `neuromodulation`
- `population_coding_range`
- `adaptive_spiking`
- `receptor_dynamics`
- `short_term_plasticity`
- `background_noise`
- `spatial_connectivity`

### Generator Fidelity Metadata

The generator now attaches descriptive fidelity metadata for several advanced
concepts. This does not change generation behavior; it documents how faithful
the current implementation is.

The generated Nengo network may include:

```python
net.generator_fidelity = {
    "annotations": [
        {
            "concept": "...",
            "subject": "...",
            "fidelity": "placeholder|approximate",
            "reason": "...",
        }
    ]
}
```

The current default labels are:

- `homeostatic_plasticity` -> `placeholder`
- `neuromodulation` -> `approximate`
- `short_term_plasticity` -> `approximate`
- `spatial_connectivity` -> `approximate`

## 7. Pipeline (Legacy `run_pipeline` Orchestration)

> **`run_pipeline()` orchestrates the full Nengo simulation path. For the
> NIR compile path, use `compile_to_nir()` directly — it does not call
> `run_pipeline()` internally.**

### Main File

- `neurocnl/pipeline.py`

`run_pipeline(...)` now executes this high-level order:

1. `parse_spec_text()`
2. `lower_to_ir()`
3. `plan_backend_support()`
4. `default_params_with_provenance()`
5. `validate_spec()`
6. `generate()`
7. Optional Nengo or Nengo-Loihi simulation
8. Optional Layer 3 assertion generation and `pytest` execution

Key current behavior:

- Any parse error stops the pipeline before validation if there are no valid
  parsed sentences, or returns early with a partial-parse error if some lines
  failed.
- Any IR lowering failure stops the pipeline before validation and generation.
- Any validation failure stops the pipeline before generation.
- Planner output is stored on `PipelineResult`, but is advisory unless another
  stage fails.
- Loihi Layer 1 warnings are merged into planner warnings and can downgrade a
  planner verdict from `faithful` to `approximate`.
- Successful generation copies `net.generator_fidelity` onto
  `PipelineResult.generator_fidelity`.
- `probe_all=True` adds probes to all ensembles.
- Simulation output includes extracted probe data, a summary, and wall time.
- Layer 3 assertions are generated into a temporary file and run with
  `python -m pytest`.

`PipelineResult` now contains additive internal fields beyond the public
contract, including:

- `ir`
- `planner`
- `generator_fidelity`

These are useful for internal tooling, backend API surfacing, and frontend
analysis panels, but they are not the original minimal pipeline contract.

## 8. API Layer

### Main Files

- `backend/app/routers/parse.py`
- `backend/app/routers/validate.py`
- `backend/app/routers/simulate.py`
- `backend/app/services/neurocnl_bridge.py`
- `backend/app/schemas/parse.py`
- `backend/app/schemas/validate.py`
- `backend/app/schemas/simulate.py`

### `POST /api/parse`

Returns per-line parsing results, including parser error details and rewrite
hints when parsing fails.

### `POST /api/validate`

Returns:

- `layer1`
- `layer2`
- `overall`
- `backend_support` when planner data is available

Layer 1 warnings are surfaced separately from hard failures.

### `POST /api/simulate`

Returns the normal simulation payload and may also include:

- `backend_support`
- `generator_fidelity`

These fields help explain whether a backend mapping is clean and whether some
advanced generator behaviors are only approximate.

## Summary

The current implementation is broader and more layered than the older
reflex-arc-only descriptions:

- **21 parser-recognized concepts** (cnl_grammar.md is the canonical reference).
- **All 21 concepts lower to IR** via `lower_to_ir()`; the extent of structure
  written into `NetworkIR` varies by concept (populations/connections vs.
  metadata-only attributes).
- 26 general Layer 1 invariants, plus 4 Loihi-specific hard invariants.
- Layer 1 warnings for timing and backend-compatibility mismatches.
- 9 Layer 2 cross-sentence checks.
- Nengo generation (legacy path) still depends on 4 core concepts, with many
  newer concepts applied directly inside the generator.
- The primary supported product surface is the direct `CNL → IR → NIR` path
  via `compile_to_nir()` — no Nengo network is constructed.
- Backend planning and generator fidelity now provide explicit advisory signals
  where support is approximate rather than silently implied.
- See `docs/support_matrix.md` for per-concept NIR fidelity verdicts.
