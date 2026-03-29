# Fix Windows Installer Scope

**Priority:** P2-Medium
**Effort:** 1 day
**Labels:** packaging, windows

## Problem
`nmtk/installer/windows/setup.iss` Inno Setup script only builds the neurocnl frontend, not the full neuro_toolkit launcher. Needs updating to build from `nmtk/neuro_toolkit/build/windows/` and include all module assets.

## Acceptance Criteria
- [ ] Windows installer builds the full launcher
- [ ] Installs and launches correctly
- [ ] All modules accessible

## Notes
Maps to POC-100-TASKS.md T4-3.
