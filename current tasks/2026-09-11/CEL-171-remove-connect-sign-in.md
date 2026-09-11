# CEL-171 — Remove app sign-in step entirely for connecting to an already-running dev server

## Problem
After CEL-115/CEL-170, a returning device reconnected silently, but a device
connecting to a known/running server for the very first time still hit the
full username/password sign-in form.

## Fix
1. **`connect_notifier.dart`**: `connect`/`reconnectOnOpen` now only probe host
   reachability (`ConnectService.probe`, the existing `/health` check) — no
   credential is collected or sent. `ConnectRequest` is host-only.
   `ConnectService.login`/`reconnect` (the credentialed calls) are
   deliberately left unused by this flow; they remain for reference/possible
   reuse, are still covered by `connect_service_test.dart`, and are untouched.
2. **`server_connect_screen.dart`**: Form now asks only for the server
   address ("Connect to your server" / "Connect"). Username and password
   fields are removed. "Could not reach `<host>`…" failure messaging is
   unchanged in wording.
3. Tests updated: `connect_notifier_test.dart`, `server_access_gate_test.dart`,
   `server_connect_screen_test.dart`, and `dev_offline_navigation_test.dart`
   (title copy only) to match the no-credential flow.

`server_setup_screen.dart` and the SSH/admin provisioning flow are untouched,
per scope.

## Known gap (flagged, not fixed here)
The backend's `POST /api/launcher/auth/login` still unconditionally
bcrypt-checks a username/password (`nmtk/launcher_control/launcher_auth.py`).
Since this flow no longer calls `login`/`reconnect`, the session it produces
has an empty `sessionToken`. Code paths that forward that token as a bearer
credential (`riverpod_providers.dart`'s `adminToken`, `module_uri_resolver.dart`)
will not be authenticated against endpoints that check it. This ticket's
scope was explicitly the 3 frontend files; making the backend accept
no-credential sessions for the connect-to-existing-server path is follow-up
work.

## Verification
```bash
cd nmtk/neuro_toolkit
flutter analyze lib/features/server/connect/connect_notifier.dart lib/screens/server_connect_screen.dart
flutter test test/features/server/connect/connect_notifier_test.dart test/server_connect_screen_test.dart test/server_access_gate_test.dart test/dev_offline_navigation_test.dart
```
All pass (25 tests). `provision_notifier_test.dart`/`provision_service_test.dart`
fail on this branch for an unrelated pre-existing reason (missing
`moduleEnvironment` param from a prior commit), not touched by this change.
