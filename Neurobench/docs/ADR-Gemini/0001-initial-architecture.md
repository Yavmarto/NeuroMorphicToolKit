# ADR 0001: Initial Architecture of Neurobench

## Status
Accepted

## Context
Neuromorphic computing lacks standardized metrics for comparing models and hardware. NMTK requires a dedicated service to perform standardized benchmarking and testing of neuromorphic models across various hardware configurations.

## Decision
We will develop `Neurobench` as the core module for benchmarking, focusing on evaluating performance, latency, and energy efficiency. It will be architected to run in containerized environments (Docker) to ensure consistent dependency management for the varying metric-collection scripts.

## Consequences
- **Positive:** Enables objective comparisons and metrics collection.
- **Negative:** Creating standardized benchmarks for highly diverse hardware and models is technically challenging.
