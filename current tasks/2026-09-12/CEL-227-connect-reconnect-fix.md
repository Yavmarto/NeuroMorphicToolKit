# CEL-227 — Fix dev server connect stuck on reconnecting

## Root cause
1. `_connectToHost` published `reconnecting` then awaited `saveTarget`; a keychain/prefs write failure left phase stuck at `reconnecting` forever.
2. `ServerAccessGate` kept the workspace visible during reconnect, so empty `ModuleState` flashed **NeuroStudio Not Available** under the overlay.

## Fix
- `connect_notifier.dart`: publish `connected` before persistence; wrap probe/save in try/catch; skip duplicate `reconnectOnOpen` while `reconnecting`.
- `server_access_gate.dart`: hide workspace child during reconnect overlay (`Visibility` + `maintainState`).
- Tests: save-failure regressions + gate hides workspace while reconnecting.

## Verify
```bash
cd nmtk/neuro_toolkit
flutter test test/features/server/connect/ test/server_access_gate_test.dart test/server_connect_screen_test.dart test/dev_offline_navigation_test.dart
```

Unblocks [CEL-226](/CEL/issues/CEL-226); QA on [CEL-228](/CEL/issues/CEL-228).
