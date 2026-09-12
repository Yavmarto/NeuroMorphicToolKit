# CEL-158 — Local APK delivery script

## Deliverable
`scripts/serve_apk.sh` — build and serve NMTK Android APK + macOS DMG over LAN.

## Usage
```bash
scripts/serve_apk.sh                    # profile build (default) + serve both on :8765
scripts/serve_apk.sh --debug            # debug build
scripts/serve_apk.sh --release          # release build
scripts/serve_apk.sh --apk-only         # skip the DMG
scripts/serve_apk.sh --dmg-only         # skip the APK
scripts/serve_apk.sh --skip-build       # serve existing artifacts
```

## CEL-157 follow-up (2026-09-11)
Changed default build type from release to profile, made debug/profile/release all
explicit flags, and added macOS DMG building (`nmtk/installer/macos/create-dmg.sh`)
alongside the APK — both build outputs are staged in `build/serve/` and served
together, each with its own download URL and QR code.

## CEL-157 follow-up (2026-09-11, codesign race)
`flutter build macos` failed with `codesign ... replacing existing signature` /
`errSecInternalComponent`. Root cause: this repo has many agent runs building/testing
the same `nmtk/neuro_toolkit` checkout concurrently, and two `flutter build macos`
invocations racing on the same `build/macos/Build/Products/.../App.framework` corrupt
its codesign. Fixed by serializing builds across `serve_apk.sh` runs with a lock dir
(`build/.../.serve_apk_build.lock`, 10 min timeout) and retrying the macOS build step
up to 3 times with a 5s backoff, since a clean re-run of the same command succeeds
once the race clears.

## Verified
- LAN IP detection (outbound probe + ifconfig fallback)
- HTTP serve returns 200 for APK
- Port kill/reuse on re-run
- qrencode graceful degrade
- `bash -n scripts/serve_apk.sh` syntax check

## Docs
AGENTS.md Developer paths section updated.
