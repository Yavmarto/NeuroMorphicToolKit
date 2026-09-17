# ADR 0007: Network Partitioner

## Status
Accepted

## Context
Large SNN models may exceed the capacity of a single neuromorphic chip or core. Deploying such models requires splitting the network across multiple cores or chips while minimizing inter-partition communication latency.

## Decision
Implement a `partitioner.py` service that splits networks using a "partition by population" strategy, keeping whole neuron populations together on the same core to minimize cross-chip synaptic communication. The partitioner calculates latency overhead estimates for inter-partition connections and respects hardware constraints (neurons per core, synapses per core) from the target's JSON profile.

## Consequences
- **Positive:** Population-level partitioning preserves local connectivity patterns and minimizes inter-chip spike routing; hardware constraint validation prevents deployments that would exceed core capacity.
- **Negative:** Population-level granularity cannot split a single large population across cores; latency estimates are approximations that may not match actual chip interconnect performance.
