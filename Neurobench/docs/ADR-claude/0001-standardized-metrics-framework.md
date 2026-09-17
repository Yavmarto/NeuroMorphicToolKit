# ADR 0001: Standardized Metrics Framework

## Status
Accepted

## Context
The neuromorphic computing field lacks agreed-upon metrics for comparing models and hardware, making cross-platform comparisons meaningless without standardization. Different research groups measure different quantities in different units.

## Decision
Define 8 standard metrics (accuracy, latency_ms, power_mw, memory_kb, spike_fidelity, stopping_distance, joules_per_spike, energy_uj) as an `AllowedMetric` enum in the benchmark contracts. All benchmark results are stored uniformly in SQLite with per-result seed tracking for reproducibility. Null metrics are permitted for partial benchmarks where not all measurements are available.

## Consequences
- **Positive:** Enables objective, reproducible cross-platform comparisons; the enum-based metric set prevents ad-hoc metric proliferation.
- **Negative:** Fixed metric set may not capture domain-specific measurements; adding new metrics requires contract schema changes across the stack.

## Status Update (2026-07-16 audit)

`AllowedMetric` in `neurobench/neurobench/contracts/benchmark_contracts.py` (lines 7-25) is a `Literal[...]` type alias, not an enum — `StrEnum` is used elsewhere in the same file (`MetricProvenance`, `JobStatus`) but not for `AllowedMetric`. The set has also grown from the original 8 to 16 values: the original 8 (`accuracy`, `latency_ms`, `power_mw`, `memory_kb`, `spike_fidelity`, `stopping_distance`, `joules_per_spike`, `energy_uj`) plus 8 more, explicitly labeled in the source as "Upstream NeuroBench library metrics" (`mse`, `r2`, `smape`, `activation_sparsity`, `synaptic_operations`, `membrane_updates`, `parameter_count`, `connection_sparsity`). This directly contradicts the "prevents ad-hoc metric proliferation" rationale above — the metric set has in fact grown by 100% since this ADR was accepted.
