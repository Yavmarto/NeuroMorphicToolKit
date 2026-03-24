# Neurobench: add property tests for benchmark invariants

**Module:** Neurobench
**Spec Source:** Neurobench/neurobench_spec.md#NB-CT2, Neurobench/neurobench_spec.md#NB-ES1, Neurobench/neurobench_spec.md#NB-RP1, Neurobench/neurobench_spec.md#NB-RP2
**Labels:** feature, cdd-pbt, migration, properties

## Objective
Express the scientific and benchmarking invariants as Hypothesis suites so agent-written implementations cannot pass with inconsistent metrics or invalid regressions.

## Conversion
- Add property tests for non-negative latency, power, memory, and spike-fidelity metrics.
- Add properties for regression-threshold handling so failures happen only when configured thresholds are crossed.
- Add robustness-curve properties that preserve monotonic degradation under increasing perturbation rates.

## Contract Targets
- Neurobench/neurobench/app/contracts/result_contracts.py

## Property Targets
- Neurobench/neurobench/tests/properties/test_metric_bounds.py
- Neurobench/neurobench/tests/properties/test_robustness_curves.py
- Neurobench/neurobench/tests/properties/test_regression_thresholds.py

## Acceptance Checks
- Property tests cover cross-target comparisons, regression diffs, and robustness sweeps.
- Hypothesis counterexamples are deterministic under the CI profile.
- No benchmark result can report negative physical metrics.

## Dependencies
- blocked-by local issue id: NB-CDD-001
