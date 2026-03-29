# [PROD-01] End-to-End Integration Tests (ref: issue 001)

**Module**: nmtk-launcher
**Phase**: Production
**Priority**: P0
**Effort**: Large (4+ days)
**Labels**: `nmtk-launcher`, `phase:production`, `priority:critical`

## Acceptance Criteria

- [ ] Test full workflow: launch → start all modules → navigate to each → verify UI loads
- [ ] Test module failure recovery: kill a backend → verify launcher detects and restarts
- [ ] Test on all 3 platforms (macOS, Linux, Windows)
- [ ] Integration test automated in CI
