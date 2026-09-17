# ADR 0002: Three-Layer Validation

## Status
Accepted

## Context
Parsed CNL specifications must be validated against biological physics, inter-sentence consistency, and target hardware constraints before code generation. A single monolithic validator would be unmaintainable and unable to report layer-specific errors.

## Decision
Implement three validation layers: Layer 1 enforces 18 biological invariants (e.g., `threshold_above_resting`, `refractory_period_positive`, `excitatory_weight_sign`) derived from NeuroML constraints. Layer 2 performs cross-sentence validation for connectivity, naming consistency, and population references. Hardware-specific validators (Akida, SpiNNaker2, Teensy) check target-specific constraints. Each layer can pass or fail independently with specific error messages.

## Consequences
- **Positive:** Layered validation provides precise, actionable error messages at each level; biological invariants catch physically impossible specifications before they reach simulation.
- **Negative:** Three layers increase validation complexity and execution time; biological invariant thresholds require domain expertise to calibrate correctly.

## Status Update (2026-07-16 audit)
The named invariant count and hardware-validator claims are stale. `ALL_INVARIANTS` in `neurocnl/neurocnl/layers/layer1_invariants.py` now has 26 entries, not 18. `layer1_validator.py`'s own docstring states hardware-backend support (loihi/akida/spinnaker/teensy) was removed 2026-07-04 as dead code. The named invariant `excitatory_weight_sign` doesn't exist; the closest current function is `inhibitory_weight_negative`.
