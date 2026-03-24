# Neurobench: extract benchmark and regression contracts from the spec

**Module:** Neurobench
**Spec Source:** Neurobench/neurobench_spec.md#NB-B1, Neurobench/neurobench_spec.md#NB-B2, Neurobench/neurobench_spec.md#NB-CT1, Neurobench/neurobench_spec.md#NB-R1, Neurobench/neurobench_spec.md#NB-R2
**Labels:** feature, cdd-pbt, migration, contracts

## Objective
Convert the benchmark catalog, benchmark run inputs, cross-target comparison rows, and regression baseline thresholds from prose acceptance criteria into executable contract models.

## Conversion
- Create contract models for benchmark definitions, benchmark run requests, benchmark results, baseline threshold files, and cross-target comparison payloads.
- Move any ad-hoc schema duplication behind a shared contract layer.
- Reject malformed benchmark manifests before jobs start.

## Contract Targets
- Neurobench/neurobench/app/contracts/benchmark_contracts.py
- Neurobench/neurobench/app/contracts/regression_contracts.py
- Neurobench/neurobench/tests/contracts/test_benchmark_contracts.py

## Property Targets
- Neurobench/neurobench/tests/properties/test_benchmark_request_properties.py
- Neurobench/neurobench/tests/properties/test_regression_contract_properties.py

## Acceptance Checks
- Invalid benchmark definitions fail contract validation with actionable messages.
- Baseline files require metric thresholds and comparison direction metadata.
- Cross-target result rows serialize and deserialize without field loss.
