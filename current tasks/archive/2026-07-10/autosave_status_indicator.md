# Saving / all-changes-saved indicator in the Studio toolbar

## Problem
The local-storage autosave (`WorkspaceController._persist()` and the newly
added `_scheduleCanvasAutosave()` — see `autosave_missing_eval_grid_fix.md`
in this same folder) writes silently in the background. There was no way
for the user to tell whether their latest edits had actually been persisted
yet, so a hot restart or crash mid-write could lose work with no warning.

## Fix
- New `providers/autosave_status_provider.dart`: `AutosaveStatus` enum
  (`saving`/`saved`) + `AutosaveStatusController`, tracking an in-flight
  counter since `_persist()` and `_scheduleCanvasAutosave()` are two
  independent writers that can overlap.
- `providers/workspace_provider.dart`: `_persist()` now delegates to an
  async `_doPersist()` that reports `markSaveStarted()`/`markSaveFinished()`
  around the write, guarded with `ref.mounted` checks (the provider can be
  disposed mid-write, e.g. in tests or during teardown).
- `screens/studio/workspace_file_io.dart`: `_scheduleCanvasAutosave()`
  reports `markSaveStarted()` the instant a change is detected (not just
  once the 300ms debounce fires) and `markSaveFinished()` once the write
  resolves, guarded with `mounted` checks.
- `screens/studio/studio_top_bar.dart`: new `_AutosaveStatusIndicator`
  (`ConsumerWidget`, `ref.watch(autosaveStatusProvider)`) inserted into the
  toolbar row right after the Save button — a small spinner while saving,
  a green checkmark (`AppTheme.healthyColorOf`, matching `_PlayStopButton`'s
  existing success color) once all writes have settled. Scoped to the
  ambient autosave only; the manual "Save Workspace" file export keeps its
  own existing snackbar feedback.

Note: an initial version added a 500ms "cooldown" debounce before flipping
back to "saved" to avoid flicker during rapid typing, but this left a
pending `Timer` past widget disposal in several `studio_screen_test.dart`
tests (`!timersPending` assertion). Removed — the indicator flips to
"saved" immediately when the in-flight counter reaches zero, which is
simpler and doesn't leak timers.

## Verification
- `dart run build_runner build`: generated `autosave_status_provider.g.dart`
  cleanly (a handful of unrelated `*_provider.g.dart` files also picked up
  fresh source-hash stamps as an incidental side effect of the codegen run
  — no semantic changes).
- `dart analyze` on all changed/new files: clean (only pre-existing
  warnings at unrelated lines).
- `flutter test test/providers_test.dart test/screens/studio_screen_test.dart`:
  58 tests, same single pre-existing failure as baseline (an unrelated
  RenderFlex overflow), no new failures.
- Not verified in a live browser/device session — no dev-server launch
  config exists for this app yet and standing one up (Flutter web build +
  backend service dependencies) was out of scope for this change; visual
  correctness rests on the passing widget tests (which do render the full
  toolbar) plus code review against the existing `_PlayStopButton` spinner
  precedent.
