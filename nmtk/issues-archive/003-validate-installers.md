# Validate Platform Installers

**Priority:** Low — Real-world deployment
**Effort:** 3 days (across platforms)
**Source:** POC-100-TASKS.md T4-1, T4-2, T4-3

## Problem

macOS DMG (`create-dmg.sh`), Linux AppImage (`appimage.sh`), and Windows Inno Setup (`setup.iss`) all exist but have never been tested. Windows installer only builds neurocnl frontend, not full launcher.

## Acceptance Criteria

- [ ] macOS: `flutter build macos --release` -> `create-dmg.sh` -> DMG mounts -> app launches from /Applications
- [ ] Linux: AppImage tested on Ubuntu 22.04+
- [ ] Windows: Inno Setup updated to build from `nmtk/neuro_toolkit/build/windows/` with all module assets
