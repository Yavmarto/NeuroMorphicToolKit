# [POC-01] Bootstrap neurocli Package and User-Facing Entry Point

**Module**: neurocli
**Phase**: POC
**Priority**: P0
**Effort**: Medium (2 days)
**Labels**: `neurocli`, `phase:poc`, `priority:critical`, `tooling`, `cli`
**Source**: 02-Apr-2026 folder review

## Problem

`neurocli` currently has planning intent but no implementation. The folder contains only an archived issue describing a "Project Scaffolder" CLI, with no package structure, entry point, or tests. Until the package exists, there is no scriptable terminal-first front door to the NMTK ecosystem.

## Acceptance Criteria

- [ ] Create the initial Python package layout for `neurocli`
- [ ] Add a `pyproject.toml` with dependency and entry-point configuration
- [ ] Expose a top-level executable command such as `neuro`
- [ ] `neuro --help` renders successfully with no import errors
- [ ] Add a command namespace structure that can support `new`, `install`, `run`, and `status`
- [ ] Configure logging and exit-code behavior suitable for CLI use
- [ ] Add at least one smoke test for command invocation
