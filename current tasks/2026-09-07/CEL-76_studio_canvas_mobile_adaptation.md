# CEL-76 — NeuroCNL Studio & canvas mobile adaptation via shared widgets

Parent: CEL-72.

## Findings
Items 2 and 3 from the issue (canvas overlays → `showModalBottomSheet` on compact
widths, single-column reflow for `SetupStep`/`RunStep`/`DeployReviewStep` gated on
`NmtkShellTokens.compactBreakpoint`) were already implemented in the working tree
before this task started — verified by reading `canvas_screen.dart`,
`mobile_canvas_chrome.dart`, `run_step.dart`, `studio_result_visualizer.dart`, and
`deploy_hardware_step.dart` directly. No changes were needed there.

## Changes made
1. **Unified stepper lock treatment** — extracted `NmtkWorkflowLockedTreatment`
   into `lib/ui_core/widgets/workflow_step_row.dart` (dim + optional tooltip for a
   locked step indicator). Wired into:
   - `lib/features/neurocnl/widgets/workflow/pipeline_stepper.dart`
   - `lib/features/neurocnl/widgets/workflow/snn_workflow_stepper.dart` (`_StageCell`)
   - `lib/features/neurocnl/widgets/workflow/snn_mobile_workflow_stepper.dart`
   Each site's original opacity (0.38 desktop, 0.3 mobile) and tooltip behavior
   preserved — full badge/icon unification was intentionally NOT done, since the
   desktop chip (filled brand-color circle) and mobile chip (outlined status pill)
   are deliberately different designs; only the truly duplicated "locked" wrapper
   was shared.
2. **Breakpoint literals replaced with named local constants** (not the shared
   `compactBreakpoint` token — these gate on local pane/viewport width via
   `LayoutBuilder`, not app-shell width, so they are a different semantic and each
   got a documented `static const double` instead):
   - `akida_setup_pane.dart`, `akida_visualization_panel.dart`,
     `generated_code_pane.dart`, `hub_artefact_card.dart`,
     `network_graph_view.dart`, `simulation_control_panel.dart`

## Verification
From `nmtk/neuro_toolkit`:
```bash
flutter test test/features/neurocnl/screens/studio_mobile_step_drawer_test.dart \
  test/features/neurocnl/widgets/snn_mobile_workflow_stepper_test.dart \
  test/features/neurocnl/screens/studio_responsive_audit_test.dart
# 49/49 passed, including CanvasScreen/StudioScreen baselines @ 360x640, 390x844, 414x896
flutter analyze lib/features/neurocnl lib/ui_core/widgets/workflow_step_row.dart lib/ui_core/widgets/workflow_stage_tile.dart
# No issues found
```

Not run: full-package `flutter test`/`flutter analyze` — a concurrent agent
(CEL-73/CEL-74) had unrelated in-flight edits to `server_connect_screen.dart` /
`server_setup_screen.dart` / neurobench widgets in the same working tree at the
time, which showed pre-existing unrelated failures (ListTile/DecoratedBox ink
assertions in server-connect tests) not touched by this change.
