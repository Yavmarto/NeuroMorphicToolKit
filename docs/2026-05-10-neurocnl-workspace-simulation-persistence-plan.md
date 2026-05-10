# NeuroCNL Workspace, File I/O, and Simulation Persistence Plan

## Scope

Write set for the implementation this plan describes:

- `neurocnl/frontend/**`
- `docs/**` for follow-up notes only if the workspace file format or user-visible behavior needs documentation

Primary goal:

- Fix broken save/load/rename workflows in NeuroCNL Studio.
- Introduce a real workspace file format that can contain multiple `.cnl` models.
- Persist simulation results per model inside the workspace so reopening the workspace does not require rerunning simulation.
- Keep cached results attached to the correct model when the active file changes.
- Add a UI surface to compare models and their cached results.

Non-goals for the first implementation:

- Cross-module launcher changes
- Backend API contract changes unless a missing field makes result persistence impossible
- A generic shared widget in `nmtk_ui_core` unless the comparison UI proves reusable across modules

## Current State

Observed from the current `neurocnl/frontend` code:

1. Native file load is effectively broken.
   - `lib/services/import_text_file_picker_stub.dart` always returns `null`.
   - Result: desktop/native "Load .cnl file" does nothing.

2. Native save is misleading.
   - `lib/services/platform_helper_stub.dart` writes to `getApplicationDocumentsDirectory()` with no user-selected location.
   - Result: "Save" works only as a silent internal export, not as expected file save behavior.

3. The editor already has multi-file in-memory state, but not a durable workspace file.
   - `lib/models/workspace_file.dart`
   - `lib/providers/workspace_provider.dart`
   - Current persistence is `shared_preferences` cache, not an explicit workspace artifact the user can save/open.

4. Simulation state is not file-scoped.
   - CNL simulation is stored globally in `lib/providers/pipeline_provider.dart`.
   - Canvas preview is stored globally in `lib/providers/canvas/simulation_provider.dart`.
   - Result: simulation output is tied to the current session state, not to a specific model file in the workspace.

5. File rename support exists only in provider logic.
   - `WorkspaceNotifier.renameFile()` exists.
   - The current tab strip does not expose a rename action.

## Target Behavior

1. `Save` on a CNL file should save the active model to a user-chosen path.
2. `Load` should let the user import one or more `.cnl` files on native and web.
3. `Save Workspace` should write a single workspace artifact containing:
   - workspace metadata
   - all model files
   - the active file id
   - UI restore state that is safe to persist
   - cached simulation results keyed by file id
4. `Open Workspace` should fully restore the editor tabs and cached results.
5. Running simulation for file A must persist only to file A.
6. Switching to file B must not destroy file A's cached result.
7. Switching back to file A must restore its cached result without rerunning simulation.
8. The UI must expose a comparison view for multiple models and their cached results.

## Proposed Design

### 1. Introduce a versioned workspace format

Add a new JSON-backed workspace document, for example:

- extension: `.neurocnl-workspace.json`
- top-level fields:
  - `version`
  - `savedAt`
  - `files`
  - `activeFileId`
  - `activePanel`
  - `selectedDeployTarget`
  - `comparisonSelection`

Each file entry should contain:

- `id`
- `name`
- `path` only as advisory metadata
- `content`
- `dirty`
- `isUntitled`
- editor selection/scroll restore fields
- `simulationCache`

`simulationCache` should start with CNL pipeline simulation only:

- `status`
- `duration`
- `savedAt`
- `result`
- `error`

If canvas preview persistence is needed in the same change, add a second optional slot such as `previewCache`. Do not overload one result type for both systems.

### 2. Split transient UI state from durable workspace state

Persist in the workspace file only what is needed to restore user work:

- file tabs
- active file
- chosen panel
- deploy target
- simulation caches

Do not persist purely session-local or derived values unless they materially improve reopen behavior.

### 3. Make simulation persistence file-scoped

Refactor `workspaceProvider` to become the owner of per-file cached simulation data.

Recommended direction:

- add a typed simulation cache model under `lib/models/`
- extend `WorkspaceFile` with an optional simulation cache field
- add notifier methods such as:
  - `saveSimulationResultForActiveFile(...)`
  - `clearSimulationResultForFile(...)`
  - `simulationResultForFile(String fileId)`

Then wire the simulation flow:

- after `PipelineNotifier.runGenerateAndSimulate()` succeeds, push the result into the active workspace file cache
- when active file changes, hydrate `pipelineProvider` from that file's cached simulation result
- when the active file has no cached result, clear pipeline simulation state only, not the whole workspace

This keeps the result bound to the file id instead of the global provider instance.

### 4. Fix platform file I/O properly

Replace the current native stub behavior with real open/save flows.

Expected changes:

- add a native-capable picker/saver dependency such as `file_selector`
- implement:
  - `save text file as...`
  - `open text file(s)`
  - `save workspace as...`
  - `open workspace...`

Behavior rules:

- `.cnl` files save as plain text
- workspace files save as JSON
- native save should return the actual chosen path
- web should continue using browser download/upload behavior

### 5. Expose rename and workspace actions in the Studio UI

Update the file tab strip and/or toolbar to include:

- `Rename`
- `Save File`
- `Save Workspace`
- `Open File`
- `Open Workspace`

Rename UX can be lightweight:

- context menu on tab, or
- inline edit for the active tab, or
- simple dialog

The important part is that rename updates the tab label and persists into the workspace file.

### 6. Add a model/result comparison panel

Add a new Studio panel, likely adjacent to `Preview`, backed by cached workspace results.

Recommended first-pass UI:

- table or cards listing each file
- columns:
  - model name
  - simulation cached/not cached
  - duration
  - wall time
  - sensory spike count
  - motor spike count
  - sensory mean rate
  - motor mean rate
  - latency
- row action to activate/open that model

This should compare cached results across files without rerunning anything.

If detailed probe-level comparison is wanted later, add it as a second step after the summary comparison ships.

## Implementation Order

### Phase 1: Platform file I/O repair

- Implement native file open/save APIs.
- Add tests for native/web save and load behavior.
- Keep the current single-file editor behavior working before adding workspace save/open.

### Phase 2: Workspace schema and serialization

- Add new workspace models and JSON codecs.
- Extend `WorkspaceFile` to carry typed simulation cache.
- Add notifier methods for workspace save/open and per-file simulation cache updates.
- Preserve compatibility with existing `shared_preferences` bootstrap as a fallback.

### Phase 3: Simulation cache integration

- Persist successful simulation results into the active file.
- Restore cached simulation state when switching active files or reopening the workspace.
- Clear only the active file's simulation state when explicitly requested.

### Phase 4: UI actions and comparison panel

- Add rename/open/save workspace affordances.
- Add comparison panel using per-file cached summaries.
- Ensure panel switching and active-file switching do not drop cached data.

## Likely Files

- `neurocnl/frontend/lib/models/workspace_file.dart`
- new workspace result/cache models under `neurocnl/frontend/lib/models/`
- `neurocnl/frontend/lib/providers/workspace_provider.dart`
- `neurocnl/frontend/lib/providers/pipeline_provider.dart`
- `neurocnl/frontend/lib/screens/studio_screen.dart`
- `neurocnl/frontend/lib/services/platform_helper*.dart`
- `neurocnl/frontend/lib/services/import_text_file_picker*.dart`
- new workspace file service(s) under `neurocnl/frontend/lib/services/`
- widget tests under `neurocnl/frontend/test/`

## Verification

Minimum checks for the implementation:

- `cd neurocnl/frontend && flutter test`

Must-have test coverage:

1. Workspace serialization round-trip with multiple files and cached results.
2. Active-file switch restores the correct cached simulation result.
3. Reopening a saved workspace restores tabs, active file, and cached results.
4. Native file open no longer returns `null` by default.
5. Native save returns the chosen path and writes the expected file contents.
6. Rename persists through workspace save/open.
7. Comparison panel renders mixed states correctly:
   - files with results
   - files without results
   - active row selection

## Acceptance Criteria

- Desktop/native `Load` visibly imports a `.cnl` file.
- Desktop/native `Save` writes where the user chose, not only to an internal app-documents path.
- Users can save and reopen a multi-file NeuroCNL workspace artifact.
- Simulation results persist per model across file switches and app/workspace reopen.
- The comparison UI shows per-model cached results without requiring reruns.
