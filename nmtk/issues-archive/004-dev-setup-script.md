# Create One-Command Development Setup Script

**Priority:** Medium — Developer experience
**Effort:** 1 day
**Source:** POC-100-TASKS.md T4-4

## Problem

Setting up the full dev environment requires manual steps across 7+ directories.

## Acceptance Criteria

- [ ] `scripts/dev-setup.sh` exists at repo root
- [ ] Inits and updates all git submodules
- [ ] Creates per-module Python venvs or shared venv
- [ ] Installs all Python backends in editable mode
- [ ] Runs `flutter pub get` in all frontend directories
- [ ] Verifies all health endpoints
- [ ] Works on macOS (primary) and Linux

## Archived Predecessors

- `issues-archive/22mar7_create_one_command_development_setup_scr.md`
