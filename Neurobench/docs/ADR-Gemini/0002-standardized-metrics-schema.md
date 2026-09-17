# ADR 0002: Standardized Metrics Schema

## Status
Accepted

## Context
Comparing biological precision models running on standard x86 GPUs against 4-bit quantized SNNs on Loihi hardware requires a singular benchmark format. Variable-sized arrays and ad-hoc metrics result in convoluted visualization logic and biased scientific reporting.

## Decision
We enforce a standardized tracking database `neurobench.sqlite`. Any internal bench script outputs performance criteria mapped exactly to centralized keys (Accuracy, Fidelity, Energy in Joules, Process Latency, Parameter Density).

## Consequences
- **Positive:** Assures parity when cross-plotting hardware deployments and software models inside unified graphs inside the Flutter frontend.
- **Negative:** Extremely rigid. Complex or novel hardware evaluations (like "routing congestion" on specific SpiNNaker arrays) may not have a natively supported database key.
