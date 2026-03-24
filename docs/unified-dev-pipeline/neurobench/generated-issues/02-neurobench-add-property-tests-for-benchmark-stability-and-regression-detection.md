# Neurobench: add property tests for benchmark stability and regression detection

**Module:** Neurobench
**Spec Source:** Neurobench/neurobench_spec.md#NB-S1, Neurobench/neurobench_spec.md#NB-S2
**Labels:** feature, cdd-pbt, migration, properties

## Objective
Add Hypothesis property tests for benchmark result stability, score ordering, and regression detection accuracy.

## Conversion Steps
- [ ] Add properties for benchmark score reproducibility under seed control
- [ ] Add properties for regression detection: degradation beyond threshold always flagged
- [ ] Add properties for score format round-trip (serialize → deserialize → compare)

## Contract Targets

## Property Targets
- `Neurobench/neurobench/tests/properties/test_benchmark_properties.py`
- `Neurobench/neurobench/tests/properties/test_regression_properties.py`

## Acceptance Checks
- [ ] 200+ examples generated per property in CI
- [ ] Regression beyond threshold never passes silently
- [ ] Score round-trips preserve precision to 6 decimal places

## Dependencies
- blocked-by: `NB-CDD-001`
