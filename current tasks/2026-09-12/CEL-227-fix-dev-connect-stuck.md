# CEL-227 — Fix dev server connect stuck on reconnecting

## Root cause
Dev/profile `_connectToHost` set `ConnectPhase.reconnecting` then awaited `TargetStore.saveTarget` (keychain write). If secure storage threw, phase never advanced — infinite reconnect overlay with NeuroStudio empty-state bleeding through the semi-transparent barrier.

## Fix
- Publish `connected` immediately after successful `/health` probe; persist target in non-blocking try/catch.
- `server_access_gate`: hide workspace during reconnect (`Visibility` + `maintainState`).
- Guard `reconnectOnOpen` against re-entry while already reconnecting.

## Tests
21 passed in connect_notifier, server_access_gate, server_connect_screen suites.
