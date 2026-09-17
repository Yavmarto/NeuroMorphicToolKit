# ADR 0001: Initial Architecture of Neurohub

## Status
Accepted

## Context
A major barrier in neuromorphic computing is the lack of standardized environments to share artefacts like SNN models, encoding presets, and datasets.

## Decision
We will create `Neurohub` to act as the community registry and repository for NMTK. It will store and share pre-trained SNN models, Neuromorphic datasets, hardware profiles, NeuroCNL templated specifications, and benchmark baselines.

## Consequences
- **Positive:** Strongly encourages community collaboration and artefact reuse.
- **Negative:** Requires robust backend storage, version control for data, and community standard enforcement.
