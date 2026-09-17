# ADR 0005: Parameter Sweep Engine

## Status
Accepted

## Context
Researchers need to explore how SNN behavior changes across parameter ranges (e.g., varying synaptic weights or time constants), but unbounded sweeps could overwhelm server resources.

## Decision
Implement a sweep runner that accepts a parameter path (dot-notation addressing like `nodes.<id>.<param>`), range, and step count capped at `MAX_SWEEP_STEPS = 20`. Each step deep-copies the graph, modifies the target parameter, and runs a preview simulation via the existing preview runner. Results are collected into a `SweepResponse`.

## Consequences
- **Positive:** Parameter exploration is bounded and predictable; deep-copy isolation ensures sweep steps cannot interfere with each other.
- **Negative:** The 20-step hard limit constrains fine-grained exploration; deep copying large graphs is memory-intensive for complex topologies.
