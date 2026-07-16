# ADR 0001: Scaffolding-First CLI

## Status
Accepted

## Context
The NMTK ecosystem lacks a unified command-line entry point for project bootstrapping. GUI-only access through the desktop launcher limits CI/CD pipeline integration, headless server operation, and power-user workflows that benefit from scriptability.

## Decision
Design neurocli as a Typer/Click-based CLI focused initially on project scaffolding (`neuro new --framework lava --target loihi2 --task kws`), generating complete project boilerplate including `pyproject.toml`, requirements, example scripts, and README. Future expansion will add module management (`run`, `status`, `install`) commands.

## Consequences
- **Positive:** Scaffolding-first approach delivers immediate value for new projects without requiring full feature parity with the GUI; CLI enables integration into automated pipelines.
- **Negative:** Scaffolding-only initial scope means users still need the desktop launcher for module management; maintaining feature parity with the GUI over time increases maintenance burden.

## Status Update (2026-07-16 audit)
The illustrative example combo this ADR cites (`neuro new --framework lava --target loihi2 --task kws`) was never implemented as named. There is no top-level `lava` framework key; `lava` only appears as a target value under framework `nir` (i.e. `--framework nir --target lava_sim`). `loihi2` is not a supported target at all. The real supported (framework, target) combos live in `neurocli/neurocli/new.py`'s `_COMBOS` dict: `(nir, snntorch)`, `(nir, lava_sim)`, `(nir, sc_neurocore)`, `(neurocnl, pynq)`, `(akida, brainchip)`, `(neurocnl, neurosim)`.
