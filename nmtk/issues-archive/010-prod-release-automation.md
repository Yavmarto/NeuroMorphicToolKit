# [PROD-01] Release Automation

**Module**: root-infrastructure
**Phase**: Production
**Priority**: P0
**Effort**: Large (4+ days)
**Labels**: `root-infrastructure`, `phase:production`, `priority:critical`

## Acceptance Criteria

- [ ] Semantic versioning across all modules (coordinated releases)
- [ ] Automated changelog generation from conventional commits
- [ ] Automated Docker image tagging and pushing to registry
- [ ] Automated desktop app packaging (macOS DMG, Linux AppImage, Windows installer)
- [ ] One-command release: `make release VERSION=x.y.z`
