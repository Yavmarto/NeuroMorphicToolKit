# Autosave drops the Train/Eval canvas ("eval grid") on hot restart

## Problem
Local-storage autosave (`WorkspaceController._persist()` / `_buildInitialState()`,
key `neurocnl_workspace_state_v1`) only ever serialized/restored
`WorkspaceState` (open files, CNL text = "the model"). It never captured or
restored `CanvasController.pipeline`/`pipelinePhases` (the Train/Eval DAG =
"the eval grid"), `SimulationController.results`, or `TrainingHistory`. After
a Hot Restart, the model came back but the eval grid was always empty. This
was the explicitly-flagged "out of scope" follow-up from
`current tasks/2026-07-08/workspace_save_missing_train_eval_canvas.md`, which
fixed the same gap for the manual "Save/Open Workspace" file flow only.

## Fix
- `providers/workspace_provider.dart`:
  - Exposed the storage key as `WorkspaceController.workspaceStorageKey`.
  - `_buildInitialState()` now stashes any `'canvas'` section found in the
    cached/bootstrap JSON into `_pendingCanvasRestorePayload`, consumed once
    via `consumePendingCanvasRestorePayload()` (mirrors the existing
    `_pendingLegacyMigrationText` pattern). Still backward-compatible with
    older cached blobs that are the flat `WorkspaceState` JSON with no
    `'workspace'`/`'canvas'` wrapper.
  - `_persist()` now reads back whatever `'canvas'` section is already on
    disk and re-includes it, so a workspace-only mutation (e.g. typing)
    can't clobber the canvas data written by the new autosave listener
    below.
- `screens/studio/workspace_file_io.dart`:
  - Extracted `_buildCanvasSection()` out of `_saveWorkspace()` so both the
    file-save path and the new local-storage autosave build the identical
    `'canvas'` JSON shape (`pipeline`, `pipelinePhases`, `simulationResults`,
    `simulationCurrentTime`, `trainingHistory`).
  - Added `_scheduleCanvasAutosave()`: a 300ms-debounced write of
    `{...buildRestorePayload(), 'canvas': _buildCanvasSection()}` to the
    same `workspaceStorageKey`. Debounced because
    `SimulationController.currentTime` ticks continuously during playback.
- `screens/studio_screen.dart`:
  - Registered `ref.listenManual` subscriptions on `canvasProvider`,
    `canvas_sim.simulationProvider`, and `trainingHistoryProvider` in
    `initState`, each triggering `_scheduleCanvasAutosave()`; closed in
    `dispose()` alongside the debounce `Timer`.
  - In the existing startup `postFrameCallback`, added a call to
    `consumePendingCanvasRestorePayload()` and, if present, feeds it into
    the existing `_restoreCanvasFromPayload()` (unchanged, reused verbatim
    from the save/open flow).

## Verification
- `dart analyze` on the 3 changed lib files + the updated test file: clean.
- `flutter test test/providers_test.dart`: 26/26 pass, including two new
  regression tests (legacy flat-cache backward compat, and canvas section
  round-tripping through `_persist()`/`_buildInitialState()`).
- `flutter test test/screens/studio_screen_test.dart`: same 1 pre-existing
  failure as on unmodified code (`git stash` compare) — an unrelated
  RenderFlex overflow in "debounces parse and validate while typing in CNL",
  not caused by this change.
