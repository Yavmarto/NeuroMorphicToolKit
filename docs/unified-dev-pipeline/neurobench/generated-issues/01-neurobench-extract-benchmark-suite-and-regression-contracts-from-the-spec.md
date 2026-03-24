# Neurobench: extract benchmark suite and regression contracts from the spec

**Module:** Neurobench
**Spec Source:** Neurobench/neurobench_spec.md#NB-D1, Neurobench/neurobench_spec.md#NB-D2, Neurobench/neurobench_spec.md#NB-D3
**Labels:** feature, cdd-pbt, migration, contracts

## Objective
Create Pydantic contracts for benchmark suite definitions (task name, dataset, metric), run results (score, timestamp, hardware tag), and regression thresholds. Enforce that no benchmark run can silently degrade.

## Conversion Steps
- [ ] Create BenchmarkSuite contract: task name non-empty, dataset path exists, metric in allowed set
- [ ] Create RunResult contract: score >= 0, timestamp ISO-8601, hardware tag non-empty
- [ ] Create RegressionThreshold contract: tolerance > 0, comparison direction (higher/lower is better)

## Contract Targets
- `Neurobench/neurobench/contracts/benchmark_contracts.py`
- `Neurobench/neurobench/contracts/regression_contracts.py`

## Property Targets

## Acceptance Checks
- [ ] Benchmark contracts reject empty task names
- [ ] Run result contracts reject negative scores
- [ ] Regression thresholds enforce tolerance > 0
