# CEL-228 QA Report — Dev server connect after CEL-227 fix

**Date:** 2026-09-12  
**Verifier:** QA agent  
**Build mode tested:** debug/profile (widget tests; `ConnectBuildPolicy.requiresCredentialAuth == false`)

## Verdict: PASS

## 1. CEL-227 acceptance widget tests

```bash
cd nmtk/neuro_toolkit
flutter test test/features/server/connect/ test/server_access_gate_test.dart test/server_connect_screen_test.dart test/dev_offline_navigation_test.dart
```

**Result:** `00:03 +33 ~1: All tests passed!`

Key regressions verified:
- `connect still succeeds when saving the target fails`
- `reconnectOnOpen does not leave reconnecting when save fails`
- `shows the workspace immediately when reconnect succeeds` (workspace hidden during reconnect overlay)
- `connecting does not touch ref after the gate unmounts the form`

## 2. Live dev backend (192.168.2.90)

```bash
bash scripts/check_dev_server.sh 192.168.2.90
```

**Result:** All services healthy, including `launcher-control (port 8090)` and `suite_api (port 9000)`.

Live probe (same endpoint `ConnectService.probe` uses):

```
GET http://192.168.2.90:8090/health → 200 {"status": "ok"}
GET http://192.168.2.90:9000/api/suite/health → 200 (version: dev)
```

## 3. End-user path checklist (debug/profile)

| Check | Result | Evidence |
|-------|--------|----------|
| No infinite **Reconnecting to your server…** overlay | PASS | CEL-227 regression tests; `connected` published before persistence |
| NeuroStudio module surface opens (not **NeuroStudio Not Available**) | PASS (indirect) | Gate hides workspace during reconnect; reconnect-ok test shows workspace after settle |
| Retry/Change server when backend unreachable | PASS | `server_access_gate_test` reconnect-fail → connect form; `dev_offline_navigation_test` dev bypass |
| Connect to 192.168.2.90 launcher (8090) | PASS | Live health probe 200; debug/profile auto-probes default host |

## 4. Notes

- Release-build credential sign-in retry (`server_connect_screen_test` retry case) is skipped in debug/profile (`skip: !ConnectBuildPolicy.requiresCredentialAuth`). CEL-227 fix targets the debug/profile probe path reported in CEL-226.
- Full headed `flutter run -d macos` GUI walkthrough was not re-run; automated coverage + live backend health satisfy the acceptance bar for this blocker fix.

## Unblocks

[CEL-226](/CEL/issues/CEL-226) can resume now that [CEL-227](/CEL/issues/CEL-227) fix is verified.
