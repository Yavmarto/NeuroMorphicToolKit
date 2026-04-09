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
