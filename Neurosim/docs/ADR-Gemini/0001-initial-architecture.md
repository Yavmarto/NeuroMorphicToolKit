# ADR 0001: Initial Architecture of Neurosim

## Status
Accepted

## Context
Before deploying costly physical neuromorphic chips, developers must validate their Spiking Neural Network models in software.

## Decision
We will use `Neurosim` as the native robust simulation environment within NMTK. Designed for testing neuromorphic models, fine-tuning parameters, and software-level validation, it will interface with Docker to support complex simulation environments.

## Consequences
- **Positive:** Avoids mandatory hardware dependency during the prototyping phase.
- **Negative:** Simulations, especially of complex SNNs, can be computationally heavy, requiring substantial memory and CPU/GPU resources.
