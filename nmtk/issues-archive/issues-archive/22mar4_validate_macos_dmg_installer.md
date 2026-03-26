# T4-1: Validate macOS DMG installer

- **Problem:** `nmtk/installer/macos/create-dmg.sh` exists but has never been tested. It builds from Flutter release artifacts.
- **Fix:**
  1. Build Flutter app: `cd nmtk/neuro_toolkit && flutter build macos --release`
  2. Run DMG creator: `cd nmtk/installer/macos && bash create-dmg.sh`
  3. Test: mount DMG → drag to Applications → launch
- **Effort:** 1 day
- **Verify:** App launches from /Applications on a clean macOS machine
