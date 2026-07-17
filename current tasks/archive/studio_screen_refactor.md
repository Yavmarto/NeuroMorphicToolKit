# Studio Screen Refactor Plan

## Verified Implementation Status (2026-07-04)

**Status: DONE (goal achieved via a different file layout than proposed).**

`neurocnl/frontend/lib/screens/studio_screen.dart` is now **1,235 lines** (down from the 5,153 cited in the
plan), and only `_StudioScreenState`, `StudioScreen`, and two small data classes
(`_WorkspaceTabFileViewData`, `_WorkspaceTabViewData`) remain in it — matching the plan's intent that only
the orchestrator stay behind. A `lib/screens/studio/` subdirectory exists with ~9,500 lines split across 20
files, e.g. `file_tab_strip.dart`, `pipeline_stage_area.dart`, `play_stop_button.dart`,
`studio_top_bar.dart`, `workspace_file_io.dart`, `workspace_open_overlay.dart`, plus subdirectories
`deploy/` (deploy_workspace_panel.dart, akida/lava/sc_neurocore-fpga workspaces, hardware target catalog),
`hardware_target/` (hardware_target_dialog.dart, add_hardware_target_form.dart), `shared/`
(studio_widgets.dart), and `steps/` (setup_step.dart, run_step.dart, results_step.dart, notebook_step.dart,
results_comparison.dart, etc.).

**Discrepancy from the plan:** the actual split does not use the file names the plan specified
(`studio_layout.dart`, `studio_editor_workspace.dart`, `studio_panel_workspace.dart`,
`studio_compiled_artifacts.dart`, `studio_deploy_panel.dart`, `studio_hardware_targets.dart`,
`studio_hardware_workspaces.dart`, `studio_shared_widgets.dart` do not exist under those names) — the
refactor was evidently done independently/organically (e.g. `pipeline_stage_area.dart`,
`compiled_artifacts/compiled_artifacts_panel.dart`, `deploy/deploy_workspace_panel.dart`,
`hardware_target/hardware_target_dialog.dart` cover equivalent functionality, and `steps/` is an added
structure beyond what this plan described), and has since grown further (e.g. `results_comparison.dart`,
`notebook_step.dart`) as the app evolved past this plan's scope.

Both `neurocnl/frontend/test/screens/studio_screen_test.dart` and
`neurocnl/frontend/test/screens/studio_responsive_audit_test.dart` referenced in the plan's execution rules
exist.

**Missing:** nothing outstanding — the structural goal (small orchestrator + focused extracted files) is
met and exceeded; the specific task-by-task file plan here is stale relative to what was actually built.

`studio_screen.dart` is 5,153 lines containing ~55 classes/enums/functions. This plan splits it into focused files with zero behavior changes.

---

## Target file structure

```
lib/screens/
  studio_screen.dart                  ← orchestrator only (~280 lines)

lib/screens/studio/
  studio_layout.dart                  ← _StudioLayoutMode enum, _buildDesktopLayout, _buildTabletLayout, _buildCompactLayout, _buildWorkspaceFrame
  studio_editor_workspace.dart        ← _buildEditorWorkspace, _FileTabStrip, _ViewModeToggle, _ToggleSegment, _SegmentPosition
  studio_panel_workspace.dart         ← _buildPanelWorkspace, _PipelineWorkspaceHeader, _PlayStopButton, _PlayStopButtonState, _MobilePipelineBackButton, _KeepAliveWrapper, _DurationSlider
  studio_compiled_artifacts.dart      ← _CompiledArtifactsPanel, _CompiledArtifactsHeader, _CompiledArtifactsMetricChip, _GeneratedCodePane, _GeneratedCodePaneState, _GeneratedCodeKind, _VDivider, _NengoParamChip, _StepErrorPane, _showCompiledArtifactsDialog
  studio_deploy_panel.dart            ← _DeployWorkspacePanel, _DeployTargetWorkspace, _HardwareTargetRow, _TargetNavTile, _ArtifactsButton, _TrainButton, _deployTargets, _DeployTargetData, _targetForId, _targetLabel
  studio_hardware_targets.dart        ← _HardwareTargetDialog, _HardwareTargetDialogState, _DialogTargetTile, _AddHardwareTargetForm, _AddHardwareTargetFormState, _HardwareTargetDialogData, _SavedHardwareTargetEntry, _HardwareTargetFormResult, _StudioFormField, _mergeHardwareTargetEntries
  studio_hardware_workspaces.dart     ← _StudioTeensyWorkspace, _StudioPynqWorkspace, _StudioAkidaWorkspace, _StudioLavaWorkspace, _teensyPhaseLabel
  studio_shared_widgets.dart          ← _StudioPhaseBanner, _StudioInlineError, _StudioStatusLine, _StudioHardwareActionWrap, _StudioHardwareActionSpec, _StudioHardwareActionVariant, _WorkspaceOpenOverlay, _WorkspaceOpenOverlayState
```

---

## What stays in `studio_screen.dart`

Only `_StudioScreenState` (the stateful orchestrator) and `StudioScreen`. All private classes it builds are extracted and imported from the `studio/` subdirectory. Total remaining: ~280 lines.

---

## Task list

### Task 1 — Create `studio_shared_widgets.dart`
Extract: `_StudioPhaseBanner`, `_StudioInlineError`, `_StudioStatusLine`, `_StudioHardwareActionWrap`, `_StudioHardwareActionSpec`, `_StudioHardwareActionVariant`, `_WorkspaceOpenOverlay`, `_WorkspaceOpenOverlayState`

These have no dependencies on `_StudioScreenState`. No imports change in the caller — just move the class bodies.

Imports needed: `flutter/material.dart`, `nmtk_ui_core`, `../theme/app_theme.dart`

### Task 2 — Create `studio_hardware_workspaces.dart`
Extract: `_StudioTeensyWorkspace`, `_StudioPynqWorkspace`, `_StudioAkidaWorkspace`, `_StudioLavaWorkspace`, `_teensyPhaseLabel`

Dependencies: all four hardware deploy providers, `studio_shared_widgets.dart` (for `_StudioPhaseBanner` etc).

### Task 3 — Create `studio_hardware_targets.dart`
Extract: `_HardwareTargetDialog`, `_HardwareTargetDialogState`, `_DialogTargetTile`, `_AddHardwareTargetForm`, `_AddHardwareTargetFormState`, `_HardwareTargetDialogData`, `_SavedHardwareTargetEntry`, `_HardwareTargetFormResult`, `_StudioFormField`, `_mergeHardwareTargetEntries`

Dependencies: registry service providers, `studio_shared_widgets.dart`.

Note: `_SavedHardwareTargetEntry` and `_HardwareTargetFormResult` are data classes used as callback arguments — keep them in this file, add barrel exports if needed.

### Task 4 — Create `studio_deploy_panel.dart`
Extract: `_DeployWorkspacePanel`, `_DeployTargetWorkspace`, `_HardwareTargetRow`, `_TargetNavTile`, `_ArtifactsButton`, `_TrainButton`, `_deployTargets`, `_DeployTargetData`, `_targetForId`, `_targetLabel`

Dependencies: `studio_hardware_workspaces.dart`, `studio_hardware_targets.dart`, `studio_shared_widgets.dart`, `simulator_panel.dart`.

`_showCompiledArtifactsDialog` stays here (called from `_DeployWorkspacePanel`).

### Task 5 — Create `studio_compiled_artifacts.dart`
Extract: `_CompiledArtifactsPanel`, `_CompiledArtifactsHeader`, `_CompiledArtifactsMetricChip`, `_GeneratedCodePane`, `_GeneratedCodePaneState`, `_GeneratedCodeKind`, `_VDivider`, `_NengoParamChip`, `_StepErrorPane`, `_showCompiledArtifactsDialog`

Dependencies: providers, `studio_shared_widgets.dart`.

### Task 6 — Create `studio_editor_workspace.dart`
Extract: `_FileTabStrip`, `_ViewModeToggle`, `_ToggleSegment`, `_SegmentPosition`

These are pure UI components for the editor top bar. No provider dependencies (they receive callbacks).

Dependencies: `nmtk_ui_core`, `../theme/app_theme.dart`, `../providers/studio_view_mode_provider.dart`.

`_buildEditorWorkspace` is a method on `_StudioScreenState` — it stays in `studio_screen.dart` but is simplified by importing these widgets.

### Task 7 — Create `studio_panel_workspace.dart`
Extract: `_PipelineWorkspaceHeader`, `_PlayStopButton`, `_PlayStopButtonState`, `_MobilePipelineBackButton`, `_KeepAliveWrapper`, `_DurationSlider`

Dependencies: providers, pipeline_bar widget, `studio_shared_widgets.dart`.

`_buildPanelWorkspace` stays in `_StudioScreenState` but becomes short.

### Task 8 — Create `studio_layout.dart`
Extract: `_StudioLayoutMode` enum and `_StudioMobileSection` enum.

These enums are used across methods in `_StudioScreenState` — keep them as a thin shared-types file.

### Task 9 — Trim `studio_screen.dart`
After all extractions, `studio_screen.dart` contains only:
- `_StudioMobileSection` (or import from `studio_layout.dart`)
- `StudioScreen` widget
- `_StudioScreenState` with all business logic methods: `_triggerRun`, `_triggerStop`, `_handleSave`, `_handleLoad`, `_handleOpenWorkspace`, `_handleSaveWorkspace`, `_handleRenameActiveFile`, `_selectDeployTarget`, `_scheduleSimulatorPreflight`, `_loadDefaultHardwareTargets`, `_loadHardwareTargetDialogData`, `_saveHardwareTarget`, `_selectHardwareDevice`, `_syncSelectedHardwareProvider`, `_scheduleDeployValidation`, `_syncSpecFromWorkspace`, `_openInNeurosim`, `_showMessage`, `_buildDesktopLayout`, `_buildTabletLayout`, `_buildCompactLayout`, `_buildWorkspaceFrame`, `_buildEditorWorkspace`, `_buildPanelWorkspace`, `_buildPanelContent`

---

## Execution rules

1. **One task at a time.** Complete each file, verify `flutter analyze` passes, then move on.
2. **No behavior changes.** The split is purely mechanical — move class bodies verbatim, add the necessary imports.
3. **Visibility.** All extracted classes remain private (`_` prefix). They are only accessible within the `studio/` directory via direct import in `studio_screen.dart`. No public API surface changes.
4. **Import strategy.** `studio_screen.dart` imports each new file with a relative path: `import 'studio/studio_shared_widgets.dart';` etc.
5. **Run `flutter test test/screens/studio_screen_test.dart test/screens/studio_responsive_audit_test.dart`** after Task 9 to confirm no regressions.

---

## Estimated line counts after split

| File | Est. lines |
|---|---|
| `studio_screen.dart` | ~280 |
| `studio_layout.dart` | ~20 |
| `studio_shared_widgets.dart` | ~250 |
| `studio_hardware_workspaces.dart` | ~700 |
| `studio_hardware_targets.dart` | ~650 |
| `studio_deploy_panel.dart` | ~400 |
| `studio_compiled_artifacts.dart` | ~600 |
| `studio_editor_workspace.dart` | ~350 |
| `studio_panel_workspace.dart` | ~300 |
| **Total** | **~3,550** (excl. boilerplate imports) |
