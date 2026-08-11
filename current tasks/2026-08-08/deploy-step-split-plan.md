# Split hardware Deploy into its own 7th Studio step

## Context

Studio's pipeline currently has 6 steps (`selectData → defineModel → defineTrain → defineEval → run → deploy`), where the last step is internally named `deploy` but labeled "Results" and renders training curves/metrics. The actual hardware-deploy UI (target picker, readiness/verdict, bundle info, on-device benchmark, per-class accuracy, layer spike stats, attribution-map heatmap, and hub-publish card) only appears as a **modal dialog** launched from inside that Results step — cramped into dialog width/height constraints, which is the "crowded popup" the user is describing. Hub-sharing is also split across two disconnected entry points: a one-click "Share to Hub" button in the Results sidebar, and a richer hub card inside the deploy dialog.

Goal: promote hardware deploy to its own numbered step (7 total), move all hub-sharing into that step, and use the extra page space to de-clutter the existing on-device inference/prediction visualizations (no new on-device *training* visualization — confirmed with the user that no on-device training capability exists anywhere in the stack; Akida only supports inference/benchmark on the card, never fine-tuning/learning).

## Step model changes

- [studio_pipeline_steps.dart](neurocnl/frontend/lib/models/studio_pipeline_steps.dart) — append `'deployHardware'` to `kStudioPipelineStepNames` after `'deploy'`. Leave the existing `'deploy'` entry (→ Results) untouched, so no `migrateStepName` shim is needed for old saved workspaces.
- [snn_workflow_stepper.dart](nmtk_ui_core/lib/widgets/snn_workflow_stepper.dart) — append `deployHardware` to `SnnWorkflowPhase` (after `deploy`, so existing `.index` comparisons for earlier phases stay stable), add `deployHardware: 'Deploy'` to `kSnnStepLabels`, and add its `_buildStepData` call in `build()` with a hardware-appropriate icon (e.g. `Icons.memory_outlined`, matching the icon already used on the "Deploy to Hardware" button).
- No changes needed in `studio_step_drawer.dart`, `studio_top_bar.dart`, `pipeline_stage_area.dart`, or `providers/step_unlock_provider.dart` — all iterate over `SnnWorkflowPhase.values` / `kStudioPipelineStepNames` generically, and the unlock loop (`step_unlock_provider.dart:88,93`, `for (var index = 2; index < kStudioPipelineStepNames.length; ...)`) already unlocks every step from `defineTrain` onward together, so the new step inherits the same unlock condition automatically. The existing sync assert (`step_unlock_provider.dart:17-24`) will catch any mismatch between the two lists.

## Screen wiring

- [studio_screen.dart](neurocnl/frontend/lib/screens/studio_screen.dart) — in `_buildStepContent` (`:372-385`), add an explicit `6 =>` case that wraps the existing `_buildDeployPanel()` (`:1065-1085`, already builds `_DeployWorkspacePanel` — reused as-is) in a scrollable, padded container matching the other full-page steps (see `_SetupStep`'s `SingleChildScrollView(padding: EdgeInsets.all(32))` pattern). Extract this into a small new widget, e.g. `_DeployHardwareStep`, mirroring `_ResultsStep`'s shape.
- [results_step.dart](neurocnl/frontend/lib/screens/studio/steps/results_step.dart) — remove `_openDeployDialog`/`showResultsDeployDialog` (`:895-1021`) entirely; remove the "Deploy to Hardware" `OutlinedButton` (`:1646-1655`) and its `onDeploy` wiring (`:361`, `:433`). Navigation to the new step now happens solely through the existing stepper/drawer (`ref.read(workspaceProvider.notifier).setActivePipelineStep('deployHardware')`), so no replacement button is needed in Results.
- Same file — remove `_shareToHub` (`:904-962`) and the "Share to Hub" `FilledButton` (`:1631-1644`) plus its `onShare` wiring (`:363`, `:432`). [results_comparison.dart](neurocnl/frontend/lib/screens/studio/steps/results_comparison.dart) has a duplicate Share-to-Hub button (`:208`) — remove it too. Hub sharing now lives only in `_HubPublishWorkspaceCard` inside `_DeployWorkspacePanel` (`deploy_workspace_panel.dart:188-261`), which already ships with the panel being relocated — no new hub-sharing code needed.

## De-cluttering the on-device visualization (Akida)

[akida_workspace.dart](neurocnl/frontend/lib/screens/studio/deploy/akida_workspace.dart)'s `_StudioAkidaWorkspace` currently stacks everything vertically in dialog-constrained space: host/runtime status, export banner, SDK verdict, run result, bundle info + benchmark metrics, per-class accuracy table, model-prediction summary, layer spike stats, and attribution-map heatmap. Moving to a full page removes the hard height constraint, but the content is still dense enough to warrant grouping. Reorganize into a small number of collapsible `NmtkSection`/`ExpansionTile` groups, without adding any new data or capability:
- **Readiness & Bundle** — host/runtime status, environment checks, export warnings, SDK verdict, bundle info.
- **Run & Benchmark** — action buttons (Run Model Sample, Run Benchmark, etc.), benchmark metrics, per-class accuracy table.
- **Prediction & Visualization** — model-prediction summary, layer spike stats table, attribution-map heatmap.

This is layout-only inside the existing widget; the underlying provider (`studioAkidaDeployControllerProvider`) and service calls are untouched. PYNQ/Lava/other target panels get the same crowding relief for free just from losing the dialog constraint — no changes planned there unless testing turns up a specific issue.

## Tests to update

`grep` found these referencing the button labels/step model that are changing — update alongside the code changes above, following whatever pattern each file already uses for step navigation and button lookup:
`test/widget_test.dart`, `test/pipeline_integration_test.dart`, `test/providers/step_unlock_provider_test.dart`, `test/screens/studio_screen_test.dart`, `test/screens/studio_responsive_audit_test.dart`, `test/screens/results_step_test.dart`, `test/widgets/deploy_targets_no_nested_cards_test.dart`, `test/widgets/deploy_workspace_no_section_card_test.dart`, `test/widgets/akida_runtime_reasons_test.dart`, `test/widgets/sc_neurocore_lava_workspace_no_section_card_test.dart`.

## Verification

1. `flutter analyze` in `neurocnl/frontend` — no new warnings/errors.
2. `flutter test` in `neurocnl/frontend` (targeted files above, then full suite) — all green.
3. Manual run: `flutter run -d macos` from `nmtk/neuro_toolkit`, connect to the running dev backend via "Already have a server running?" on `/setup` pointed at `192.168.68.53`. Open a workspace, confirm the stepper now shows 7 steps ending in "Deploy", Results no longer has Deploy/Share buttons, the new Deploy step renders the (now full-page, grouped) Akida workspace correctly, and "Publish to Hub" from that step still works end-to-end.
