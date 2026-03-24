# Neurosim: add property tests for canvas and simulation invariants

**Module:** Neurosim
**Spec Source:** Neurosim/neurosim_spec.md#NS-S1, Neurosim/neurosim_spec.md#NS-S2
**Labels:** feature, cdd-pbt, migration, properties

## Objective
Add Hypothesis property tests for canvas validity, sweep monotonicity, and preview time constraints.

## Conversion Steps
- [ ] Add properties for valid canvas graph construction and serialization round-trips
- [ ] Add properties ensuring sweep start < stop and step count bounds
- [ ] Add properties constraining simulation time and wall-clock limits

## Contract Targets

## Property Targets
- `Neurosim/neurosim/tests/properties/test_design_properties.py`

## Acceptance Checks
- [ ] Property tests generate 200+ examples in CI
- [ ] No negative simulation durations or step counts
- [ ] Canvas round-trip serialization preserves all connections

## Dependencies
- blocked-by: `NS-CDD-001`
