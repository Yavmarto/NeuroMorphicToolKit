# [BETA-01] macOS DMG Installer Validation (ref: issue 003)

**Module**: nmtk-launcher
**Phase**: Beta
**Priority**: P0
**Effort**: Medium (2-3 days)
**Labels**: `nmtk-launcher`, `phase:beta`, `priority:critical`

## Acceptance Criteria

- [ ] DMG builds successfully via `flutter build macos`
- [ ] App launches from DMG on clean macOS (no dev tools installed)
- [ ] All 7 backends start correctly from bundled paths
- [ ] Code signing with developer certificate
- [ ] Notarization for Gatekeeper approval
- [ ] Test on macOS 13 (Ventura) and macOS 14 (Sonoma)
