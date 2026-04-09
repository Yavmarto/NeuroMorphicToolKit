# ADR 0002: Template Bundle Architecture

## Status
Accepted

## Context
Different framework-target combinations (Lava+Loihi2, Nengo+PYNQ, Akida+BrainChip) require different boilerplate files, dependencies, and configuration patterns. A single template cannot cover all combinations without becoming unwieldy.

## Decision
Organize scaffolding templates as bundled directory trees per framework-target pair, stored as data files within the CLI package. Each template bundle generates appropriate `pyproject.toml`, dependency lists, example scripts, and configuration files. Templates reference contracts from other NMTK modules to ensure generated code is compatible with the ecosystem.

## Consequences
- **Positive:** Per-combination templates produce clean, focused project scaffolds; bundled data files ship with the CLI without external dependencies.
- **Negative:** Template combinations grow multiplicatively with new frameworks and targets; templates must be updated when upstream NMTK module contracts change.
