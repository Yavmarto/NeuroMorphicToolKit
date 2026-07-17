# Fix: Architecture "Clear Canvas" wiped the model with no confirm/undo

## Problem
`workspaces/session.neurocnl-workspace.json`'s only file had an empty
`defineModel` (Architecture) canvas even though its Train/Eval pipeline
(dataLoader/forwardPass/timeLoop/etc., 11+4 nodes) was intact. Root cause,
found by diffing the file against `git show HEAD:workspaces/session.neurocnl-workspace.json`:
the Architecture canvas and Train/Eval canvases are two independent data
paths — Architecture is driven by `WorkspaceFile.canonicalDocument` (CNL/NIR
spec), Train/Eval by `CanvasState.pipelinePhases`. At commit `f53dc0e`
(revision 8) `canonicalDocument` held a real (if incomplete — Input+Linear,
no Output yet) network; in the working copy it was `null` (revision 63),
while `pipelinePhases` had genuinely grown in between. User confirmed a
model had been defined and is now gone — a real regression, not a load bug.

The actual trigger: `neurocnl/frontend/lib/screens/canvas/canvas_screen.dart`
wires all three tabs' toolbar "Clear Canvas" button straight to
`clearArchitectureGraph()` / `clearPipelinePhase(...)` with **no confirmation
dialog** — a single accidental click on the Architecture tab's version
permanently wipes `canonicalDocument` via `canonicalDocProvider.clear()`
(`canvas_provider.dart:653-663`). Undo doesn't help: that clear pushes only
the *graph* onto `canvasProvider`'s own undo stack; `canonicalDocProvider` is
a separate provider never touched by `undo()`.

## Fix
1. **Data recovery** (root repo, not a code change): merged the last-committed
   `canonicalDocument`/`pipelineState`/cursor fields for file `untitled-1`
   from `git show HEAD:workspaces/session.neurocnl-workspace.json` back into
   the live `workspaces/session.neurocnl-workspace.json`, verified
   `pipelinePhases` node/edge counts unchanged (train 11, eval 4) before and
   after — a surgical field merge, not a blind `git checkout` (which would
   have destroyed the newer Train/Eval work). `workspaces/session2.neurocnl-workspace.json`
   had no usable backup (its `canonicalDocument` was also `null`).
2. **Root-cause fix**: added `_CanvasScreenState._confirmClearCanvas(String
   whatLabel)` (`neurocnl/frontend/lib/screens/canvas/canvas_screen.dart`) — a
   `showDialog<bool>` `AlertDialog` matching the existing
   `_confirmResumeWorkspace()` pattern in `studio_screen.dart`, styled with
   `NmtkDesignTokens.dialogShape` per `nmtk-flutter-review` design-system
   check. Wired in front of all three `onClearCanvas` callbacks (Architecture
   / Train / Eval) so each now requires an explicit "Clear" confirmation
   before the destructive call fires; "Cancel" is a no-op.

## Verification
- `dart format` + `dart analyze lib/screens/canvas/canvas_screen.dart` in
  `neurocnl/frontend`: clean (only pre-existing, unrelated warnings).
- Verified recovered JSON: `canonicalDocument` non-null for `untitled-1`,
  `pipelinePhases.train`/`.eval` node counts identical (11/4) before and
  after the merge.
- Not yet manually clicked through in a running app (no dev server/emulator
  driven this session) — do that before considering this fully closed: open
  the workspace, confirm the `defineModel` step shows Input→Linear, then
  click each tab's "Clear Canvas" and confirm the dialog blocks/allows as
  expected.

## Cross-file invariant note (for GBrain)
Architecture canvas (`canonicalDocument`) and Train/Eval canvases
(`pipelinePhases`) are separate, uncoordinated data paths in
`neurocnl/frontend/lib/providers/canonical_doc_provider.dart` and
`neurocnl/frontend/lib/providers/canvas/canvas_provider.dart` — any future
"clear"/"reset"/"import" action that touches one must not assume it also
covers the other, and vice versa.
