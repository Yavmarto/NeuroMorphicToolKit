# ADR 0001: Initial Architecture of Neurochip

## Status
Accepted

## Context
Deploying Spiking Neural Networks (SNNs) to physical neuromorphic chips is complex and heavily fragmented across vendors. NMTK needs a dedicated interface for hardware engineers to orchestrate low-level deployment.

## Decision
We will build `Neurochip` as the dedicated module designed to interface directly with various neuromorphic hardware backends (such as Intel Loihi, BrainChip Akida, and SpiNNaker). It will abstract vendor-specific details while providing low-level deployment controls.

## Consequences
- **Positive:** Abstracts hardware complexity for developers while allowing necessary control for hardware engineers.
- **Negative:** Requires continuous maintenance of vendor-specific SDKs and dependencies.
