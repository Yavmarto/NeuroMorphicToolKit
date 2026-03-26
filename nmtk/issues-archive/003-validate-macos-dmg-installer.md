# Validate macOS DMG Installer

**Priority:** P2-Medium
**Effort:** 1 day
**Labels:** packaging, macos

## Problem
`nmtk/installer/macos/create-dmg.sh` exists but has never been tested. Needs end-to-end validation: build Flutter release → create DMG → mount → drag to Applications → launch.

## Acceptance Criteria
- [ ] DMG creates successfully
- [ ] App launches from /Applications on clean macOS
- [ ] All module catalog entries load

## Notes
Maps to POC-100-TASKS.md T4-1.
