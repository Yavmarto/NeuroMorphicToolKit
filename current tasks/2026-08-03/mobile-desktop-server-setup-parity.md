# Mobile/Desktop server setup parity

## Problem

The launcher already had a dismissible server popup inside the workspace, but
`MainScreen` replaced the workspace with a full-screen setup gate whenever
bootstrap was not ready. Desktop usually bypassed that state by starting a
local control service, while mobile cannot do so and therefore appeared to
have a separate, non-dismissible setup experience.

## Resolution

- The workspace now mounts with or without a selected server. A nullable
  presentation provider exposes the active control service while operational
  code retains the required provider.
- Startup first probes the saved server and, only when that initial bootstrap
  is not ready, opens setup once for the app run. Later connection loss never
  forces the popup open again.
- One adaptive presenter owns every setup entry point: a centered dialog at
  desktop/tablet widths and a safe-area-aware, keyboard-responsive modal sheet
  below 840 logical pixels. Both embed the same `InAppBackendSetupScreen` and
  support Close, backdrop, drag, and system-Back dismissal.
- `/setup`, Change Server, disconnected empty states, quick connect, and full
  deployment all reuse the same workspace-plus-popup path. Failed/saved hosts
  and actionable bootstrap messages are carried into the form.

## Verification

- `flutter analyze`: clean.
- Targeted setup, handoff, shell, connection, and completion tests: 38 passed.
- Full launcher Flutter suite: 173 passed.
- Launcher doctor: `fatalCount: 0`, status `ok`.
- Canonical launcher guardrails: 213 launcher-control tests passed, deployment
  assets synchronized, and all 173 launcher Flutter tests passed.
