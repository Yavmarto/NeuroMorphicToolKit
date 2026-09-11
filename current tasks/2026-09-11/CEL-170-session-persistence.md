# CEL-170 — Session persistence for known dev servers

## Problem
After CEL-115, users still saw the full sign-in popup on every cold start even when they had previously connected to the same host. `reconnectOnOpen` required both a saved session token **and** a saved password, but reconnect only replays the password — so a missing/expired token blocked silent re-auth even when the credential was still in secure storage.

## Fix
1. **`connect_notifier.dart`**: Auto-reconnect now requires only a saved app password. Passes `savedUsername` through `ConnectState` for form prefill. Reconnect path forwards the saved credential when persisting the refreshed session.
2. **`server_connect_screen.dart`**: When a known server host is already saved, the address field is replaced with a read-only label; username is pre-filled from `savedUsername`.

## Verification
```bash
cd nmtk/neuro_toolkit
flutter test test/features/server/connect/connect_notifier_test.dart test/server_connect_screen_test.dart test/server_access_gate_test.dart
```

Manual: sign in once to `192.168.2.90`, quit the app, relaunch — should reconnect silently or show username/password only (no host field).
