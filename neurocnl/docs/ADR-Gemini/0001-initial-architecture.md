# ADR 0001: Initial Architecture of neurocnl

## Status
Accepted

## Context
Creating Spiking Neural Networks manually while adhering to biological constraints requires high expertise in both software engineering and neuroscience.

## Decision
We will define `neurocnl` (Conceptual Neuromorphic Language) as a module designed to translate plain-English specifications into verified Spiking Neural Networks (SNNs). It ensures compliance with biological constraints and generates models suitable for exporting to various hardware (Loihi, Lava, SpiNNaker).

## Consequences
- **Positive:** Democratizes SNN creation, significantly accelerating prototyping capabilities.
- **Negative:** Natural language interpretation mechanisms require continuous tuning and validation to avoid constraint violations.
