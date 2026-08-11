# Flutter app RAM blowup (160GB+) — round 3 (neurobench/learning poll leak)

## Problem
User reported the same RAM-blowup bug as `current tasks/2026-07-11/flutter_ram_blowup_bufferedFrames.md`
still occurring after rounds 1 and 2 were merged: app idle on the canvas (model
screen step 2), no user interaction, RAM climbs past 160GB, app stops responding.
Backend runs remote at 192.168.68.53.

## Root cause
Same bug class as round 2 (`module_notifier.dart`), but in two `neurocnl` submodule
providers that round 2 never touched (round 2 only patched `nmtk/neuro_toolkit`):

- `neurocnl/frontend/lib/providers/neurobench_panel_provider.dart`: `_startPolling`
  fired a `Timer.periodic(2s)` with no in-flight guard, and `_pollJob`/`runBenchmark`/
  `_fetchResult` called raw `http.get`/`http.post` with **no `.timeout(...)` at all**
  (bypassing `ApiClient`/`BaseHttpClient`, which has a 30s default). Against a slow/
  unreachable backend, every 2s tick could fire a new request that hangs forever,
  stacking unbounded concurrent requests.
- `neurocnl/frontend/lib/providers/learning_provider.dart`: `_startPolling` had the
  same missing in-flight guard (it does route through `ApiClient`, so it does inherit
  the 30s timeout, but could still stack concurrent requests if the backend is
  consistently slower than 30s per call).

## Fix
Mirrored the pattern already used in `training_provider.dart`/`prosthetic_sim_provider.dart`:
1. `neurobench_panel_provider.dart` — added an `_isPolling` bool guard around the
   `Timer.periodic` callback, and a 10s `.timeout(...)` on all three raw `http`
   calls (`runBenchmark`'s POST, `_pollJob`'s GET, `_fetchResult`'s GET).
2. `learning_provider.dart` — added the same `_isPolling` guard around
   `_startPolling`'s periodic callback.

## Verification
- `flutter analyze lib/providers/neurobench_panel_provider.dart lib/providers/learning_provider.dart` — no issues.
- No existing unit tests for either provider file (`find test -iname "*neurobench*" -o -iname "*learning_provider*"` — empty).

## Restart / where to notice the difference
Restart the Flutter app; leave it idle on the canvas/model screen with the remote
backend (192.168.68.53) reachable but slow — RSS should stay flat instead of growing.
No backend restart needed, frontend-only change.
