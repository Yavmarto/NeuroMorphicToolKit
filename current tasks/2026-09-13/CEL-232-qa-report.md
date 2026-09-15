# CEL-232 QA Report — Profile mobile connect without credentials

**Date:** 2026-09-13  
**Verifier:** QA agent  
**Device:** CPH2173 (Android 14, USB `aeaab7b5`)  
**Build:** `app-profile.apk` (rebuilt with CEL-226 fix)  
**Backend:** `192.168.2.90` (launcher 8090, suite_api 9000)

## Verdict: PASS

## 1. Unit / widget regressions

```bash
cd nmtk/neuro_toolkit
flutter test test/features/server/shared/target_store_test.dart \
  test/features/server/connect/connect_notifier_test.dart
```

**Result:** `00:00 +15: All tests passed!`

Key CEL-226 behaviors verified:
- `loadLastHost` returns host without secure-storage reads
- `saveTarget` skips secure storage when there are no secrets
- `reconnectOnOpen` probes saved host without reading keychain
- Unreachable host message mentions same Wi‑Fi

## 2. Live backend health

```bash
bash scripts/check_dev_server.sh 192.168.2.90 --check-only
```

**Result:** All services healthy (launcher-control 8090, suite_api 9000).

## 3. Android integration e2e (CPH2173)

```bash
cd nmtk/neuro_toolkit
flutter test integration_test/cel232_profile_mobile_connect_e2e_test.dart -d aeaab7b5
```

**Result:** `00:15 +3: All tests passed!`

| Check | Result | Evidence |
|-------|--------|----------|
| Cold start auto-probes default dev host, no credentials | PASS | `01_cold_start_connected` screenshot on device |
| Manual host-only connect reaches workspace | PASS | `02_manual_connect_form`, `03_manual_connected` |
| Unreachable host fails within ~2s probe budget | PASS | Error contains "Could not reach" + Wi‑Fi hint; elapsed < 4s |

New test file: `integration_test/cel232_profile_mobile_connect_e2e_test.dart`

## 4. Physical profile APK (shipping binary)

```bash
scripts/build_and_deliver_apk.sh --apk-only
adb -s aeaab7b5 install -r nmtk/neuro_toolkit/build/app/outputs/flutter-apk/app-profile.apk
```

| Check | Result | Evidence |
|-------|--------|----------|
| Cold start on same Wi‑Fi → NeuroStudio opens (no credential form) | PASS | `04_profile_autoconnect.png` — Setup workspace visible, no sign-in popup |
| No stuck "Reconnecting…" / "NeuroStudio Not Available" | PASS | Workspace loaded directly |
| Wi‑Fi off → actionable error quickly | PASS | `05_offline_error.png` — connect form with unreachable error |

## Unblocks

[CEL-226](/CEL/issues/CEL-226) mobile verification complete; parent can close after review.
