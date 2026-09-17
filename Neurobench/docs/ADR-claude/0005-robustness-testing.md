# ADR 0005: Robustness Testing

## Status
Accepted

## Context
Neuromorphic deployments must handle real-world conditions including sensor noise, hardware faults (stuck neurons, synapse loss), and input perturbations. Robustness evaluation requires systematic testing across fault types and severity levels.

## Decision
Implement two complementary robustness services: `perturbation_sweeper.py` for input-level noise injection (signal domain) and `fault_sweeper.py` for hardware-level fault simulation (hardware domain). Each has its own router, sweep configuration, and result contracts. Both integrate with the core benchmark runner for consistent metric collection.

## Consequences
- **Positive:** Systematic robustness evaluation across fault types produces quantitative resilience metrics; separation of perturbation and fault domains enables targeted testing.
- **Negative:** Fault models are approximations of real hardware failures; comprehensive sweep configurations can generate large result sets that are expensive to store and analyze.
