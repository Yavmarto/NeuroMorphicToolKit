# ADR 0002: Hardware Profile Manifests

## Status
Accepted

## Context
The NeuroChip module deploys SNNs to highly diverse physical processors (e.g., Intel Loihi 2 with restrictive quantization, BrainChip Akida with specific layers). Hardcoding compatibility constraints creates brittle codebases scaling linearly with target hardware acquisitions.

## Decision
All target processors are abstracted via decoupled JSON manifest profiles (`teensy41.json`, `loihi2.json`). These define constraint bounds: `neuron_capacity`, `weight_bit_widths`, `io_pins`. The system's Analyzer dynamically compares incoming SNN parameters against the requested JSON manifest.

## Consequences
- **Positive:** Allows immediate onboarding of new neuromorphic hardware limits without backend rewrites. Third parties can inject `.json` overrides.
- **Negative:** Prevents highly specific, nuanced compiler directives from running easily; complex architectures forced to squeeze into the generic schema model.
