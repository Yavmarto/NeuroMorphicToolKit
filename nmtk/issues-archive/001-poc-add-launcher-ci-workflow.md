# [POC-01] Add Launcher CI Workflow

**Module**: nmtk-launcher
**Phase**: POC
**Priority**: P0
**Effort**: Medium (2-3 days)
**Labels**: `nmtk-launcher`, `phase:poc`, `priority:critical`

## Acceptance Criteria

- [ ] Create `.github/workflows/nmtk-ci.yml`
- [ ] Flutter analyze + format check
- [ ] Run all tests in `neuro_toolkit/test/` (6 files) and `nmtk_ui_core/test/` (3 files)
- [ ] Build desktop artifacts (macOS, Linux)
- [ ] Matrix: Flutter stable + beta channels
- [ ] Workflow triggers on push/PR to nmtk/** paths
