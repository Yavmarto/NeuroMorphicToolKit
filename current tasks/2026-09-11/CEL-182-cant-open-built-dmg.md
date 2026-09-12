# CEL-182 — Can't open built dmg

## Symptom
DMG built with `./scripts/build_and_deliver_apk.sh --dmg-only` — opening the app inside
the mounted DMG on another Mac fails with "app is damaged and can't be opened" (Gatekeeper).

## Root cause
`nmtk/neuro_toolkit/macos/Runner.xcodeproj` uses Xcode "Automatic" signing with a personal
`Apple Development: armorgeddon@outlook.com (9A5NT9586Q)` certificate for the Runner target
across Debug/Profile/Release. That signature (and the per-framework signatures Xcode applies
to nested Flutter frameworks) is only trusted on the machine that built it.

`nmtk/installer/macos/create-dmg.sh` only re-signs the app when a Developer ID identity is
passed via `--sign`. `scripts/build_and_deliver_apk.sh` (the dev DMG delivery path) never
passes `--sign`, so the app shipped inside the DMG kept its personal-cert signature as-is.
On a different Mac, Gatekeeper's quarantine-triggered deep verification of that signature
fails, producing the "damaged" error — this is unrelated to notarization/Developer ID and
reproduces even before any Apple Developer Program cert exists.

Verified: re-signing the already-built `.app` ad-hoc (`codesign --force --deep --sign -`)
turns `codesign --verify --deep --strict` from failing/inconsistent into
"valid on disk" / "satisfies its Designated Requirement".

## Fix
`nmtk/installer/macos/create-dmg.sh`: when no `--sign` identity is supplied, ad-hoc re-sign
the staged `.app` (`codesign --force --deep --sign -`) before packaging it into the DMG.
Developer-ID + notarized builds (CI release workflow, or local `--sign "$IDENTITY"`) are
unaffected — they still go through `sign-and-notarize.sh`.

## Note
Even ad-hoc-signed apps still show Gatekeeper's normal first-launch prompt (right-click →
Open, or Apple Menu → System Settings → Privacy & Security → "Open Anyway") since they are
not notarized. That prompt is expected for internal test builds and is a separate concern
from the "damaged" error this fixes.

## Verified
- `bash -n nmtk/installer/macos/create-dmg.sh` syntax check
- Re-signed the existing `build/macos/Build/Products/Profile/neuro_toolkit.app` in a scratch
  copy and confirmed `codesign --verify --deep --strict --verbose=2` passes clean
