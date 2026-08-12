# Execute stage: Run+Review merged, reordered to Run → Deploy → Review

Date: 2026-08-12

## What changed

The Execute stage was `Run → Review → Deploy`. It is now:

1. **Run** — run status *and* the training result in one step. `_RunWorkspaceStep`
   shows `_RunStep` while idle/training and `_RunResultsCompletedView` once
   results exist; "Back to run status" swaps back. Finishing a run no longer
   moves the stepper.
2. **Deploy** — configuration, prerequisites and run/deploy actions only.
3. **Review** (`deployReview`) — the deploy result visualizations for every
   target. Locked until a deploy result exists.

## Naming / migration

`SnnWorkflowPhase.review` is gone; the new last phase is `deployReview` (label
"Review"). A *new* name was necessary because `migrateStepName` runs on every
normalize, read and write: legacy persisted `'review'` (and the even older
`'deploy'`) must migrate to `'run'`, and reusing the name would have rewritten
the new step on every save. Deep-link alias `?panel=comparison` now falls back
to `'run'`.

`kStudioPipelineStepNames` order still mirrors the enum (asserted in
`step_unlock_provider.dart`). `_buildStepContent` now dispatches on the step
*name*, not the raw index — the literal `4/5/6` switch silently mis-routed every
step after an insertion point.

## Result-vs-config split, per target

| target | Review | Deploy keeps |
|---|---|---|
| akida | `_AkidaResultsView` (visualization panel + sample/benchmark surface) | `_AkidaSetupPane`, `_AkidaExecutionControls` |
| lava | `_LavaResultsView` (status / spiking neurons / exec ms) | export verdict, warnings/rejections, controls |
| pynq | `_PynqResultsView` → `PynqSupportStateCard` | Controls card (`showSupportState: false`) |
| `*_sim` | `SimulatorResultsPanel(backend:)` | preflight + toolbar + Run (`showResults: false`) |
| fpga / codegen | "produces no run results" state | unchanged |

Deliberately left in Deploy: pre-run verdicts (Lava export support-state, the
simulator preflight) and `_HubPublishAction`, which is an action even though its
enablement reads result state.

Akida's Review body also renders when only a *training* snapshot exists — the
hardware activity is an overlay on the source run, not a precondition. Review's
unlock still requires a deploy result.

## State

`reviewingResults` on `studioResultSessionProvider` went from near-vestigial to
the swap driver: a clean finish sets it (replacing the old auto-advance), a
restored snapshot sets it, "Back to run status" clears it, and
`displayedSnapshot` is now just `reviewingResults ? reviewableSnapshot : null`.

Deploy results are in-memory only (`deployResultsAvailableProvider`), so Review
re-locks after a restart. No persistence work was done.

## Verification

- `flutter test` in `neurocnl/frontend`: 1772 pass (baseline before the change
  was 1767, also fully green). New file:
  `test/screens/deploy_review_step_test.dart` (per-target dispatch, empty
  states, Back to Deploy).
- `flutter test` in `nmtk_ui_core`: 192 pass, 1 pre-existing unrelated failure
  (`desktop_scaffold_test.dart` profile initials "YM").
- `flutter analyze lib test` clean in both (one pre-existing unused-import
  warning in `studio_screen_test.dart`, not from this change).
- Not yet exercised in the running app.
