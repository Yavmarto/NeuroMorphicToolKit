# Round 5 — memory-fix explanation, safe resume-workspace, stepper-stuck debug instrumentation

## Problem
Round 4 (drop the cold-start workspace auto-restore) confirmed fixed the RAM
leak (300-400MB idle vs 100+GB). Two follow-ups: (1) explain why, and provide
a safe way to bring back "resume last workspace"; (2) after that fix, the
workflow stepper became unresponsive — stuck on the Model (step 2) canvas
step, clicking any other step button does nothing, even though canvas
interaction (add nodes, import NIR) works.

## Part A — why the fix worked
`studio_screen.dart`'s startup sync (`_syncSpecFromWorkspace`) only calls
`runParseAndValidate` when the active file's CNL text is non-empty. An empty
`Untitled 1` workspace short-circuits and never touches
`CanonicalDocController`/`CanvasController._publishGraph`/validation at all.
Auto-restoring a real previous session fed a real (possibly large) CNL model
through that machinery on every cold start, and separately re-hydrated
`SimulationState.results`/`playback`/training history — payloads that, per the
autosave write side (`workspace_file_io.dart`), can contain full per-neuron/
per-timestep arrays from a completed run. That combination is what an empty
workspace structurally never reaches.

## Part B — safe opt-in resume (implemented)
`neurocnl/frontend/lib/providers/workspace_provider.dart`:
- `_buildInitialState` now stashes the cached `'workspace'` JSON (if any) in
  `_pendingResumeWorkspaceJson` instead of applying it. The `'canvas'` section
  (simulation/training/job payloads) is never read from the cache at cold
  start at all, confirmed or not.
- Added `hasPendingWorkspaceResume`, `resumeCachedWorkspace()` (applies the
  files/CNL/graph, forces `activePipelineStep` back to the default —
  never resurrects a mid-pipeline view), and `discardPendingWorkspaceResume()`.

`neurocnl/frontend/lib/screens/studio_screen.dart`:
- Startup hook now checks `hasPendingWorkspaceResume` and shows an
  `AlertDialog` ("Restore previous session?" / "Start Fresh") before doing
  anything else. Only on confirmation does it call `resumeCachedWorkspace()`;
  otherwise `discardPendingWorkspaceResume()`. Simulation results/training
  history/in-flight job ids are never restored either way.

## Part C — stepper-stuck: instrumented, not yet fixed
Two independent static traces (click handler → `setActivePipelineStep` →
`_PipelineStageArea.didUpdateWidget` → `PageView.animateToPage`) found the
whole chain logically intact: `unlockedStepsProvider`'s
`legacyWorkspaceCompatibility` unlocks all 7 steps for a fresh workspace,
`SnnWorkflowPhase` enum names match `kStudioPipelineStepNames` exactly, and no
commit in the last 24h (checked both `neurocnl` and `nmtk_ui_core`) touches
this code. Could not find the break statically, so added temporary
`debugPrint('[stepper-debug] ...')` checkpoints at the three links:
1. `studio_screen.dart`'s `onStepSelected` handler.
2. `WorkspaceController.setActivePipelineStep`.
3. `pipeline_stage_area.dart`'s `didUpdateWidget` (entry + the
   `animateToPage` skip condition).

## Next step
Run the app, click a stepper button, and check which `[stepper-debug]` line is
missing from the console — that pinpoints the actual break. Remove the
instrumentation once the real fix lands.

## Verification
- `flutter analyze` on all touched files (`workspace_provider.dart`,
  `studio_screen.dart`, `pipeline_stage_area.dart`) — clean (only pre-existing
  unrelated `unused_element` warnings).
- Manual: cold start with a cached workspace present → dialog appears;
  "Restore" shows the CNL graph with RSS still flat; "Start Fresh" behaves
  like today.

## Restart / where to notice the difference
Restart the app. With a previous session cached, you'll now see a "Restore
previous session?" dialog instead of silent auto-load. For the stepper bug,
restart and watch the debug console while clicking stepper buttons — report
back which `[stepper-debug]` checkpoint is silent.
