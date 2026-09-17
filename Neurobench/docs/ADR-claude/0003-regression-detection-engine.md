# ADR 0003: Regression Detection Engine

## Status
Accepted

## Context
As SNN models and hardware firmware evolve, performance regressions must be caught automatically to prevent deployment of degraded configurations. Manual comparison of benchmark results across runs is error-prone and unscalable.

## Decision
Implement a baseline storage system alongside results, with a `regression_service.py` that compares current results against stored baselines. A `diff_engine.py` computes deltas between runs, and `target_comparator.py` enables cross-hardware comparisons. The `encoding_comparator.py` evaluates different input encoding strategies.

## Consequences
- **Positive:** Automated regression detection catches performance degradation before deployment; multi-dimensional comparison (time, hardware, encoding) provides comprehensive analysis.
- **Negative:** Baseline management requires discipline to update when intentional changes occur; threshold configuration for "acceptable regression" is domain-specific and hard to generalize.
