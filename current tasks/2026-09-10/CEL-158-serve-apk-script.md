# CEL-158 — Local APK delivery script

## Deliverable
`scripts/serve_apk.sh` — build and serve NMTK Android APK over LAN.

## Usage
```bash
scripts/serve_apk.sh              # release build + serve on :8765
scripts/serve_apk.sh --debug      # debug APK
scripts/serve_apk.sh --skip-build # serve existing APK
```

## Verified
- LAN IP detection (outbound probe + ifconfig fallback)
- HTTP serve returns 200 for APK
- Port kill/reuse on re-run
- qrencode graceful degrade

## Docs
AGENTS.md Developer paths section updated.
