# CEL-229 — Broken icons in macOS DMG builds

## Root cause

Flutter's default icon tree-shaking subsets `zeta-icons-round.ttf` from ~270KB to ~2KB during `flutter build macos`. Missing glyphs render as empty boxes or CJK fallback characters (same class of bug as [CEL-178](../2026-09-11/) on Android).

## Fix

Pass `--no-tree-shake-icons` on all macOS Flutter build paths:

- `scripts/build_and_deliver_apk.sh` (`build_macos_with_retry`)
- `nmtk/installer/macos/build-standalone.sh`
- `.github/workflows/nmtk-ci.yml`

APK deliver path already had the flag since CEL-178.

## Verify

After rebuild, bundled font should be ~270KB:

```bash
ls -la nmtk/neuro_toolkit/build/macos/Build/Products/Profile/neuro_toolkit.app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/packages/zeta_icons/lib/assets/icons/zeta-icons-round.ttf
```

Re-run `scripts/build_and_deliver_apk.sh --dmg-only` and install the new DMG.
