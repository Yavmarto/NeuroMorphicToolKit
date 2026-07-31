# Merge Notebook into Run step + replace fake viz-demo — 2026-07-31

## Context

Two Studio UX issues, raised together:

1. Notebook was its own stepper tab (`trainingSandbox`), just a WebView into
   JupyterLab, competing for a tab slot alongside Run.
2. The stepper-bar icon button (`chart_scatter_plot`, tooltip "Visualization
   demo") opened `/viz-demo` — confirmed via its own backend docstring to be a
   **fake, canned Poisson-noise animation**, deliberately decoupled from the
   real simulation pipeline. Not tied to the user's actual network at all.

## Changes

**Notebook merge:**
- Removed `trainingSandbox` from `kStudioPipelineStepNames`
  (`models/studio_pipeline_steps.dart`) and from `SnnWorkflowPhase`
  (`nmtk_ui_core/lib/widgets/snn_workflow_stepper.dart`) — these two must stay
  in sync per `neurocnl/AGENTS.md`'s state-machine invariant, checked by
  `step_unlock_provider_test.dart` and a debug assert. Stepper is now 6 steps.
  `migrateStepName` maps old saved `'trainingSandbox'` positions to `'run'`.
- `_NotebookStep` (the JupyterLab WebView) is unchanged internally, just no
  longer a stepper page — `run_step.dart` now has an "Open Notebook" action
  that pushes it as a full-screen `MaterialPageRoute`.
- Run step got a bottom-center floating action bar: the previously-unused
  `_PlayStopButton` (fully built, never wired up) now does real work, plus
  Open Notebook, plus a state-aware Retry / Go to Results action. Metrics
  sidebar moved from right to left to make room.

**Viz-demo removal:**
- Deleted the stepper-bar button, the `/viz-demo` route, `viz_demo_screen.dart`,
  `viz_demo_provider.dart`, and the backend (`neurosim/app/routers/viz_demo.py`
  + its three synthetic-data services + all their tests). Confirmed no other
  consumers before deleting `chip_targets.py`.
- Note: a **separate, unrelated** top-level `Neurosim/` git submodule also has
  a `viz_demo.py` — different repo, not imported by `neurocnl`'s
  `backend/app/main.py` (which resolves `neurosim` to `neurocnl/neurosim`).
  Left untouched, out of scope.
- Results step gained a real "Network Playback" expandable panel using
  `AnimatedSnnPlayback` fed by the same real per-run activity export the
  sidebar's Dynamics tab already used (extracted the shared raster-resolution
  logic into `_resolveActivityRaster` so both views agree).

## Bug found and fixed along the way

The new bottom action bar's `Row` had no overflow protection — it correctly
rendered at full width, but during a split-pane collapse animation (mid-way
through the pane shrinking to zero) it would briefly get a genuinely narrow
width and assert a `RenderFlex overflowed` error. Wrapped it in a horizontal
`SingleChildScrollView` (same pattern already used for the platform-tab row)
so a narrow host degrades to scrollable instead of asserting.

## Verification

- `flutter analyze` clean (zero new errors) across `neurocnl/frontend` and
  `nmtk_ui_core`.
- `flutter test` green for: `step_unlock_provider_test.dart`, `widget_test.dart`,
  `snn_mobile_workflow_stepper_test.dart` (nmtk_ui_core), and the split-view
  regression test that surfaced the overflow bug above.
- Found 3 pre-existing broken widget tests in `studio_screen_test.dart` and
  `pipeline_integration_test.dart` — confirmed broken on a clean baseline
  (stashed all changes, re-ran, still failing, just with different symptoms).
  Unrelated to this work; flagged as a separate follow-up task.
- Backend: `ruff check` clean, `python3 -m py_compile` clean on
  `backend/app/main.py`. Could not run the Python test suite — this sandbox's
  environment is missing the `nmtk_sdk` package (a pre-existing, unrelated
  environment gap, not something this change touched).
- Not manually run in `flutter run -d macos` (no browser/simulator surface for
  a desktop Flutter app in this session) — recommend the user do a quick
  Setup → Architecture → Train → Eval → Run → Results walkthrough to eyeball
  the new action bar and Network Playback panel.
