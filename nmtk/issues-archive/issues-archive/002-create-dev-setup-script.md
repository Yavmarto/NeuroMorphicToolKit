# Create One-Command Development Setup Script

**Priority:** P2-Medium
**Effort:** 1 day
**Labels:** developer-experience, tooling
**Scope:** Cross-cutting (root level)

## Problem

Setting up the full dev environment requires manual steps across 7+ directories. There is no single command to bootstrap everything for a new developer.

## Acceptance Criteria

- [ ] `scripts/dev-setup.sh` exists and is executable
- [ ] Inits and updates all git submodules
- [ ] Creates per-module Python venvs (or shared venv)
- [ ] Installs all Python backends in editable mode
- [ ] Runs `flutter pub get` in all frontend directories
- [ ] Verifies all backend health endpoints respond
- [ ] Prints a summary of what succeeded/failed
- [ ] Works on macOS and Linux

## Notes

Maps to POC-100-TASKS.md T4-4.
