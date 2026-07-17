# Workspace save/open drops Train/Eval canvas

## Problem
Saving a workspace (`.neurocnl-workspace.json`, Studio "Save Workspace") only
serialized `WorkspaceState` (open files, CNL text, generate/sim cache, panel
selection). It never captured `CanvasController`'s `pipeline`
(`PipelineConfig`) or `pipelinePhases` (train/eval DAGs), nor simulation
results (`SimulationController.results`) or per-platform training history
(`TrainingHistory`). Reopening a saved workspace reset the Train/Eval canvas
and its results to defaults.

## Fix
- `providers/canvas/canvas_provider.dart`: added
  `CanvasController.restorePipelineState({pipeline, pipelinePhases})`.
- `providers/training_provider.dart`: added `TrainingEpochEvent.toJson()`
  (mirrors the existing `fromJson`).
- `screens/studio_screen.dart`: imported
  `models/canvas/pipeline_config.dart` and `models/canvas/pipeline_dag.dart`
  so the workspace-file-io part file can reference `PipelineConfig` /
  `PipelinePhases` by name.
- `screens/studio/workspace_file_io.dart`:
  - `_saveWorkspace` now merges a top-level `'canvas'` section into the
    saved payload: `pipeline`, `pipelinePhases`, `simulationResults`,
    `simulationCurrentTime`, `trainingHistory` — all via each model's
    existing `toJson()`.
  - `_openWorkspace` now calls a new `_restoreCanvasFromPayload()` after
    `replaceFromWorkspacePayload()`, restoring `CanvasController`,
    `SimulationController` (via its existing `restoreSnapshot()`), and
    `TrainingHistory` from that section. Missing/malformed `'canvas'` data
    (old workspace files) is a no-op, not a crash.

## Explicitly out of scope
The separate local-storage autosave path (`WorkspaceController._persist()` /
`_buildInitialState()`, key `neurocnl_workspace_state_v1`, used for
in-session restore across hot reloads) still only persists raw
`WorkspaceState.toJson()` and does not carry canvas state. Follow-up if
needed.

## Verification
- `dart analyze` on the 4 changed files: clean (only pre-existing unrelated
  warnings).
- `flutter test test/models/pipeline_config_test.dart
  test/models/pipeline_dag_test.dart`: all pass.
- `flutter test test/screens/studio_screen_test.dart`: same 4 pre-existing
  failures as on unmodified code (confirmed via `git stash`); no new
  failures introduced.
