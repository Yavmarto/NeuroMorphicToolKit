# Layer 1 Invariant Audit (Task 1)

Read-only audit. No code changed in this doc's production. Cross-checked
`neurocnl/neurocnl/layers/layer1_invariants.py`, `layer1_validator.py`,
`akida_validator.py`, `teensy_validator.py`, `spinnaker2_validator.py`,
`neurocnl_bridge.py` (`_is_nir_native()` routing), `nir_cnl/grammar_tables.py`
(`forbidden_biological_keywords`), `neurosim/app/services/nir_support.py`
+ `validation_service.py`, and `CODE_REVIEW_CRITICAL_2026-05-14.md` Phase 3.

**Correction (same day):** an earlier pass of this audit wrongly marked
`ALL_INVARIANTS` and the legacy `validate()` function as dead code, based
only on tracing the CNL-text `/api/validate` route. A second pass turned up
a *separate* live caller — the canvas/notebook LIF-population validation
flow — that does exercise `validate()`/`ALL_INVARIANTS` today. The table
below reflects the corrected, doubly-verified state. The initial
`layer1_invariants.py` edit that dropped these was reverted before being
carried into Task 2's actual changes.

## Headline finding

There are **two independent live callers** of Layer 1 validation, not one:

1. The CNL-text pipeline: `/api/validate` → `neurocnl_bridge._is_nir_native()`
   → `layer1_validator.validate_nir_records()`. This is the only path the
   Studio spec editor and the deploy-readiness work in this plan care about.
   It only ever executes `NIR_LIF_INVARIANTS` (3) and `NIR_CUBALIF_INVARIANTS`
   (4) via `_NIR_INVARIANT_REGISTRIES` (`layer1_validator.py:589-671`).
2. The canvas/notebook pipeline: `neurosim/app/services/validation_service.py`
   `_validate_nodes` calls `nir_support.validate_semantics(node.parameters)`
   for any node with `component_id in ("lif_population", "adaptive_lif")`
   (`validation_service.py:185-186`), which calls
   `layer1_validator.validate([], mapped_params)` with **no `backend` kwarg**
   (`nir_support.py:364`) — so `backend` defaults to `"nengo"` and only
   `ALL_INVARIANTS` (26 entries) is ever exercised. This is wired into
   `POST /api/neurosim/validate` (`neurosim/app/routers/validation.py`),
   mounted into the single production app in `backend/app/main.py`. Real,
   shipped canvas templates (`reflex_arc.json`, `cpg_oscillator.json`) use
   these two component types, so this is a genuinely live, user-reachable
   check — **`ALL_INVARIANTS` and `validate()` must be kept.**

The hardware-specific groups are a different story: `validate()` only merges
`LOIHI_INVARIANTS`/`AKIDA_INVARIANTS`/`SPINNAKER_INVARIANTS`/
`SPINNAKER2_INVARIANTS`/`TEENSY_INVARIANTS` into its invariant set when
`backend` equals `"loihi"`/`"akida"`/`"spinnaker"`/`"spinnaker2"`/`"teensy"`
(`layer1_validator.py:283-293`). A repo-wide grep for
`backend\s*=\s*["'](loihi|akida|spinnaker|teensy)` outside test files returns
**zero matches** — nothing in production ever passes those backend values.
The only confirmed live caller (`validate_semantics`) never passes `backend`
at all, so it always defaults to `"nengo"`. `akida_validator.py`,
`teensy_validator.py`, `spinnaker2_validator.py` are imported **only** by
`layer1_validator.py` (inside `validate()`'s dead hardware branches) and by
their own test files. `LoihiExportContract`/`AkidaExportContract`/
`TeensyExportContract` are likewise only referenced from
`neurocnl/contracts/test_*.py` and from `validate()`'s dead hardware
branches — never from any live deploy/classification path (`nir_support.py`
in `neurocnl/neurocnl/runtime/`, `deploy_targets.py`,
`notebook.py`'s `/notebook/preview`). These hardware groups and their
`validate()` branches remain genuinely dead.

`neurocnl/pipeline.py:406-446`'s `validate_spec` also has an `else` branch
that would call legacy `l1_validate` for non-NIR `ParsedSentence` input, but
`parse_spec_text` always emits NIR records for any non-empty valid spec
(the grammar blocks legacy tokens), so that branch is only reachable for a
degenerate empty-spec case — not a real caller, and not a reason to keep
anything that this audit would otherwise drop.

## Recommendation

- **Keep, unchanged**: `ALL_INVARIANTS` (26 entries,
  `layer1_invariants.py:18-357`) and the legacy `validate()` function
  (`layer1_validator.py:245-575`) — both live via the canvas LIF-population/
  adaptive-LIF validation path. Do not touch the biological invariant
  functions or the core `validate()` control flow.
- **Drop**: `LOIHI_INVARIANTS` (4, `layer1_invariants.py:364-421`),
  `AKIDA_INVARIANTS` (`akida_validator.py`), `SPINNAKER_INVARIANTS`/
  `SPINNAKER2_INVARIANTS` (`spinnaker2_validator.py`), `TEENSY_INVARIANTS`
  (`teensy_validator.py`), their corresponding `elif backend == ...:` branches
  and hardware-contract checks inside `validate()`
  (`layer1_validator.py:283-293, 320-526`), and the
  `LoihiExportContract`/`AkidaExportContract`/`TeensyExportContract` Pydantic
  models (`neurocnl/contracts/hardware_export.py`,
  `akida_deployment_contract.py`) — confirmed dead, no live caller ever
  passes a hardware `backend` value.
- **Keep, relabel for display only**: `NIR_LIF_INVARIANTS` (3),
  `NIR_CUBALIF_INVARIANTS` (4) — live via the CNL-text `/api/validate` path,
  correctly scoped to what CNL→NIR actually emits. Function names are
  technically correct but read awkwardly in the UI (`validation_panel.dart`
  label helpers); relabel display strings only, e.g.
  `nir_lif_time_constant_positive` → "LIF time constant positive". No change
  to the function names or dict keys themselves (API response shape must
  stay stable per plan Task 2 constraint).

## Per-invariant table

### `ALL_INVARIANTS` — `layer1_invariants.py:330-357` (KEEP, all 26 — live via canvas LIF-population/adaptive-LIF validation)

Not reachable from the CNL-text pipeline (blocked by `forbidden_biological_keywords`),
but live via `neurosim` canvas node validation (`validate_semantics` →
`validate([], params)`, backend defaults to `"nengo"` → this whole registry).
None of these are touched by Task 2.

| Name | Line | Decision | Rationale |
|---|---|---|---|
| threshold_above_resting | 18 | Keep | Live via canvas `lif_population`/`adaptive_lif` validation |
| refractory_period_positive | 32 | Keep | Live via canvas `lif_population`/`adaptive_lif` validation |
| time_constant_positive | 45 | Keep | Live via canvas `lif_population`/`adaptive_lif` validation |
| reset_at_or_below_threshold | 58 | Keep | Live via canvas `lif_population`/`adaptive_lif` validation |
| membrane_potential_decays_toward_rest | 72 | Keep | Live via canvas `lif_population`/`adaptive_lif` validation |
| axonal_delay_in_range | 98 | Keep | Same registry, always loaded together |
| stdp_window_positive | 111 | Keep | Same registry, always loaded together |
| stdp_weight_bounds_valid | 124 | Keep | Same registry, always loaded together |
| inhibitory_weight_negative | 144 | Keep | Same registry, always loaded together |
| population_neuron_count_within_bounds | 158 | Keep | Same registry, always loaded together |
| population_dimensions_positive | 169 | Keep | Same registry, always loaded together |
| population_radius_positive | 180 | Keep | Same registry, always loaded together |
| learning_rate_positive | 191 | Keep | Same registry, always loaded together |
| learning_rule_valid | 199 | Keep | Same registry, always loaded together |
| network_timestep_positive | 207 | Keep | Same registry, always loaded together |
| delay_quantization_step_positive | 215 | Keep | Same registry, always loaded together |
| biological_speed_multiplier_positive | 223 | Keep | Same registry, always loaded together |
| delay_quantization_not_finer_than_timestep | 231 | Keep | Same registry, always loaded together |
| lateral_inhibition_radius_positive | 243 | Keep | Same registry, always loaded together |
| homeostatic_target_rate_positive | 254 | Keep | Same registry, always loaded together |
| neuromodulation_factor_positive | 265 | Keep | Same registry, always loaded together |
| population_coding_range_positive | 276 | Keep | Same registry, always loaded together |
| adaptive_spiking_tau_positive | 287 | Keep | Same registry, always loaded together |
| stp_recovery_time_positive | 298 | Keep | Same registry, always loaded together |
| background_noise_variance_positive | 309 | Keep | Same registry, always loaded together |
| spatial_connectivity_radius_positive | 321 | Keep | Same registry, always loaded together |

### `LOIHI_INVARIANTS` — `layer1_invariants.py:416-421` (DROP, all 4 — `validate()`'s `backend="loihi"` branch is dead, `validate()` itself stays)

| Name | Line | Decision | Rationale |
|---|---|---|---|
| loihi_weight_quantizable | 364 | Drop | Only merged in when `backend=="loihi"`; no live caller ever passes that |
| loihi_ensemble_size_within_limits | 378 | Drop | Same |
| loihi_delay_in_range | 390 | Drop | Same |
| loihi_delay_ticks_within_limits | 403 | Drop | Same |

### Other hardware groups (DROP, files/dicts, not individually numbered here)

`validate()` itself is kept (live, see Headline finding); only these
hardware-specific registries and their `elif backend == ...:` branches inside
`validate()` are dropped, since no live caller ever passes a hardware
`backend` value.

| Group | File | Decision | Rationale |
|---|---|---|---|
| AKIDA_INVARIANTS | `neurocnl/layers/akida_validator.py:68` | Drop | Only merged in when `backend=="akida"`; imported only by `validate()`'s dead branch and its own test file |
| SPINNAKER_INVARIANTS | `neurocnl/layers/spinnaker2_validator.py:108` | Drop | Same, `backend=="spinnaker"` |
| SPINNAKER2_INVARIANTS | `neurocnl/layers/spinnaker2_validator.py:116` | Drop | Same, `backend=="spinnaker2"` |
| TEENSY_INVARIANTS | `neurocnl/layers/teensy_validator.py:107` | Drop | Same, `backend=="teensy"` |
| LoihiExportContract | `neurocnl/contracts/hardware_export.py:6` | Drop | Only used inside `validate()`'s dead `backend=="loihi"` branch and its own unit test |
| AkidaExportContract | `neurocnl/contracts/akida_deployment_contract.py:112` | Drop | Same, `backend in ("akida","akida2")` |
| TeensyExportContract | `neurocnl/contracts/hardware_export.py:93` | Drop | Same, `backend=="teensy"` |

### `NIR_LIF_INVARIANTS` — `layer1_invariants.py:456-460` (KEEP, all 3 — live)

| Name | Line | Decision | Rationale |
|---|---|---|---|
| nir_lif_time_constant_positive | 431 | Keep, relabel display | Live via `validate_nir_records()`; UI label → "LIF time constant positive" |
| nir_lif_resistance_positive | 439 | Keep, relabel display | UI label → "LIF resistance positive" |
| nir_lif_threshold_above_leak | 447 | Keep, relabel display | UI label → "LIF threshold above leak" |

### `NIR_CUBALIF_INVARIANTS` — `layer1_invariants.py:502-507` (KEEP, all 4 — live)

| Name | Line | Decision | Rationale |
|---|---|---|---|
| nir_cubalif_synaptic_time_constant_positive | 469 | Keep, relabel display | UI label → "CubaLIF synaptic time constant positive" |
| nir_cubalif_membrane_time_constant_positive | 477 | Keep, relabel display | UI label → "CubaLIF membrane time constant positive" |
| nir_cubalif_resistance_positive | 485 | Keep, relabel display | UI label → "CubaLIF resistance positive" |
| nir_cubalif_threshold_above_leak | 493 | Keep, relabel display | UI label → "CubaLIF threshold above leak" |

## Task 2 scope this implies

- **Keep untouched**: `ALL_INVARIANTS`, `validate()`'s core control flow
  (Pydantic `LIFNeuronContract` check, the invariant-loop at
  `layer1_validator.py:529-568`), and everything the canvas LIF-population
  path depends on. Do not delete or rename `validate()` — it is a live
  production entry point.
- Delete `LOIHI_INVARIANTS` and its 4 functions from `layer1_invariants.py`
  (`:364-421`); keep `NIR_LIF_INVARIANTS`/`NIR_CUBALIF_INVARIANTS` and their
  7 functions untouched.
- Delete `akida_validator.py`, `teensy_validator.py`,
  `spinnaker2_validator.py` and their test files (or move to an explicitly
  archived/quarantined location if the user wants to keep them for a future
  hardware-invariant revival — flagged as a decision point for Task 2).
- Inside `layer1_validator.py`'s `validate()`, delete the `elif backend ==
  "loihi"/"akida"/"spinnaker"/"spinnaker2"/"teensy":` branches
  (`:283-293` for the invariant-merge, `:320-526` for the contract/warning
  blocks) — keep the base "nengo"-default flow (`ALL_INVARIANTS` +
  `LIFNeuronContract`) intact. Drop the now-orphaned imports
  (`AKIDA_INVARIANTS`, `LOIHI_INVARIANTS`, `SPINNAKER_INVARIANTS`,
  `SPINNAKER2_INVARIANTS`, `TEENSY_INVARIANTS`, `AkidaExportContract`,
  `LoihiExportContract`) but keep `ALL_INVARIANTS`, `LIFNeuronContract`,
  `NIR_LIF_INVARIANTS`, `NIR_CUBALIF_INVARIANTS`.
- Delete `LoihiExportContract`, `AkidaExportContract`, `TeensyExportContract`
  from `neurocnl/contracts/` and their dedicated test files, once nothing
  else imports them.
- Update `neurocnl/layers/__init__.py:3,6` — currently exports
  `ALL_INVARIANTS`/`LOIHI_INVARIANTS` in `__all__`; keep `ALL_INVARIANTS`,
  drop `LOIHI_INVARIANTS`.
- Add a backend test asserting `LOIHI_INVARIANTS` (and the other hardware
  groups) no longer exist, that `ALL_INVARIANTS` is unchanged/still exercised
  by the canvas `lif_population`/`adaptive_lif` validation path, and that
  `validate_nir_records()`'s registries are unaffected.
- Update `validation_panel.dart`'s label-formatting helper(s) to special-case
  the 7 surviving `nir_*` names for nicer display text (this is scoped to the
  CNL-text validation panel only — the canvas/notebook validation UI is a
  separate surface, out of scope for this plan).
