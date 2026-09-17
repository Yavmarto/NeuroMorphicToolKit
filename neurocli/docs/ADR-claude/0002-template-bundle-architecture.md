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

## Status Update (2026-07-16 audit)
The illustrative example combos this ADR cites (Lava+Loihi2, Nengo+PYNQ, Akida+BrainChip as a "framework-target pair" naming scheme) were never implemented as named. The real supported combos live in `neurocli/neurocli/new.py`'s `_COMBOS` set: `(nir, snntorch)`, `(nir, lava_sim)`, `(nir, sc_neurocore)`, `(neurocnl, pynq)`, `(akida, brainchip)`, `(neurocnl, neurosim)`. There is no top-level "Lava" or "Nengo" framework key; `neurocnl` is used where this ADR's example said "Nengo", and `lava` only appears as a target value under framework `nir`.
