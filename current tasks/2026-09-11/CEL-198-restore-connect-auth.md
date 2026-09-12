# CEL-198 — Restore app credential auth on server connect

## Problem
CEL-171 removed sign-in and authorized connect on `GET /health` alone. Anyone on the same network/VPN who could reach the health port got workspace access with no authentication.

## Fix
Reverted the CEL-171 no-credential connect path. Connect again calls `ConnectService.login` / `reconnect` against `POST /api/launcher/auth/login`, stores the session token and password, and shows the username/password form on `ServerConnectScreen`. CEL-170 behavior kept: auto-reconnect requires only a saved password (not a live session token).

## Files
- `connect_notifier.dart` — credential-based `_authenticate` flow restored
- `server_connect_screen.dart` — sign-in form restored
- connect/gate/screen tests updated

## Verification
```bash
cd nmtk/neuro_toolkit
flutter test test/features/server/connect/connect_notifier_test.dart test/server_connect_screen_test.dart test/server_access_gate_test.dart test/dev_offline_navigation_test.dart
```
