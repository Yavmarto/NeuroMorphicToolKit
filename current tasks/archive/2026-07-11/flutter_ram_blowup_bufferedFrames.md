# Flutter app RAM blowup (164GB) — round 1 (bufferedFrames)

## Problem
User reported Flutter app RAM hit 164GB with the canvas (neurocnl) screen open and app left idle.

## Root cause
`SimulationNotifier` in `neurocnl/frontend/lib/providers/canvas/simulation_provider.dart`
appended every incoming preview frame (WebSocket stream and polling fallback) to
`state.bufferedFrames` with no cap. Each frame carries a full `PreviewPlayback` with
per-node `voltageTraces`/`spikeTrains` arrays. A long-running/looping preview run
kept growing this list without bound. Confirmed via `grep -rln "\.bufferedFrames"`
that the field has zero consumers anywhere in the codebase.

## Fix
Added `_appendBufferedFrame` helper capping the list to `_kMaxBufferedFrames = 1`
(latest frame only), used at both append sites (`_runPreviewViaWebSocket` and
`_runPreviewViaPolling`) in `simulation_provider.dart`.

## Verification
- `flutter test test/providers/canvas/simulation_provider_test.dart` — all 3 tests pass.
- `flutter analyze lib/providers/canvas/simulation_provider.dart` — no issues.

## Update: this did NOT fix the user's actual repro

User reported still hitting real (not virtual) ~164GB resident memory after a full
restart, on the **neuro_toolkit shell app** with the canvas tab open, **no preview
ever started**, backend on an **external server** — a scenario `bufferedFrames`
never touches (it only grows during an active preview stream). See round 2 below.

---

# Round 2 — unbounded HTTP polling against a slow/unresponsive external backend

## Root cause
`nmtk/neuro_toolkit/lib/services/control_api_service.dart` had **zero `.timeout(...)`**
calls across ~40 HTTP methods, all routed through `_LoggedHttpClient.send()`
(a single `http.BaseClient` override). `module_notifier.dart`'s `_startRefreshTimer`
polls every 3s for the app's lifetime (`keepAlive: true`, independent of which tab
is shown) and only guarded against `state.isLoading`/`state.hasError` — not against
a still-in-flight previous poll. Against a slow/unreachable external backend, every
request hangs forever (no timeout to cut it off) while a new one fires every 3s on
top, piling up indefinitely. `deployment_notifier.dart`'s 1s poll had the identical
shape (only active during a deployment, so not the primary driver here, but same defect).

This matches every confirmed fact: real RSS growth, happens while idle (timer runs
regardless of tab), specifically implicates an external (slow/unresponsive) backend,
and recurs after a full restart.

## Fix
1. `control_api_service.dart` — `_LoggedHttpClient.send()`: wrap `_inner.send(request)`
   and `response.stream.toBytes()` each in `.timeout(Duration(seconds: 10), onTimeout: ...)`.
   Single centralized change, covers every HTTP call made through this client.
2. `module_notifier.dart` — added `_pollInFlight` bool guard around `_pollUpdates()`
   in `_startRefreshTimer`, reset in a `finally` block.
3. `deployment_notifier.dart` — same `_pollInFlight` guard around `_startPolling`'s
   periodic callback.

## Verification
- `flutter analyze` on all 3 files — no issues.
- `flutter test` (full `nmtk/neuro_toolkit` suite): one pre-existing failure in
  `process_manager_test.dart` when run as part of the full suite (port-conflict
  flakiness across parallel process-spawning tests) — confirmed via `git stash`
  that this same failure occurs on unmodified code too, so it's unrelated to this
  change. Running `process_manager_test.dart` alone: 22/22 pass.

## Follow-up (not fixed here)
`nmtk/neuro_toolkit/lib/screens/tool_view.dart:816` keeps every opened module tab
(full embedded Flutter instance or InAppWebView) alive forever via `IndexedStack`,
never disposed on tab close. Not the confirmed driver of either repro so far, but
a real latent issue if multiple module tabs are opened in one session.

Full investigation plan: `~/.claude/plans/when-running-the-backend-pure-clarke.md`
