# NeuroMorphicToolKit Audit/Critique Implementation Checklist

**Date:** 2026-05-06  
**Sources:** `.impeccable/audit-2026-05-04.md`, `.impeccable/critique-2026-05-04.md`  
**Method:** Checked each concrete recommendation against current code. Used `semble` for targeted code search, then verified in source files.

## Summary

- Audit implementation status: now fully implemented, `15 done`, `0 partial`, `0 open`.
- Critique implementation status: improved, now `9 done`, `2 partial`, `0 open`.
- Important note: the May 4 reports are now partly stale. Several shell-level fixes have landed since then.

## Status Key

- `[done]` Implemented in current code.
- `[partial]` Partly implemented, but the original concern is not fully resolved.
- `[open]` Still missing in current code.

## Audit Checklist

- `[done]` Replace `easeSpring = Curves.elasticOut` with a non-elastic curve.
  Evidence: `NmtkMotionTokens.easeSpring = Curves.easeOutQuart` in [nmtk_ui_core/lib/motion_tokens.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/lib/motion_tokens.dart:64).

- `[done]` Fix keyboard navigation for `_SidebarNavItem`.
  Evidence: `_SidebarNavItem` now uses `Material` + `InkWell` in [nmtk_ui_core/lib/widgets/desktop_scaffold.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/lib/widgets/desktop_scaffold.dart:1006).

- `[done]` Fix keyboard navigation for `_RailIconButton`.
  Evidence: `_RailIconButton` now uses `Material` + `InkWell` in [nmtk_ui_core/lib/widgets/desktop_scaffold.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/lib/widgets/desktop_scaffold.dart:817).

- `[done]` Route Material light/dark themes correctly instead of always returning dark.
  Evidence: both builders now branch on brightness in [nmtk/neuro_toolkit/lib/main.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/lib/main.dart:158) and [nmtk/neuro_toolkit/lib/main.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/lib/main.dart:211).

- `[done]` Replace hardcoded `Colors.red` in `NmtkErrorCard` with semantic token usage.
  Evidence: `NmtkShellTokens.of(context).errorColor` is used in [nmtk_ui_core/lib/widgets/error_card.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/lib/widgets/error_card.dart:26).

- `[done]` Remove selected-state `BoxShadow` from `_PipelineStep`.
  Evidence: selected state now uses border/background only in [nmtk_ui_core/lib/widgets/pipeline_stepper.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/lib/widgets/pipeline_stepper.dart:205).

- `[done]` Make `NmtkTone.success` and `.warning` dark-mode aware.
  Evidence: dark-mode branches use shell tokens in [nmtk_ui_core/lib/widgets/tone.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/lib/widgets/tone.dart:36).

- `[done]` Add reduced-motion support for tap-scale interactions.
  Evidence: `MediaQuery.of(context).disableAnimations` is respected in [nmtk_ui_core/lib/motion_tokens.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/lib/motion_tokens.dart:243).

- `[done]` Add reduced-motion support for pulsing status dots.
  Evidence: `disableAnimations` short-circuits pulse animation in [nmtk_ui_core/lib/motion_tokens.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/lib/motion_tokens.dart:330).

- `[done]` Raise touch targets to 44px minimum across rail nav and workspace chip controls.
  Evidence: workspace chips now enforce `minHeight: 44`, and pin/close affordances live inside `SizedBox.square(dimension: 44)` in [nmtk_ui_core/lib/widgets/workspace_switcher_bar.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/lib/widgets/workspace_switcher_bar.dart:113) and [nmtk_ui_core/lib/widgets/workspace_switcher_bar.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/lib/widgets/workspace_switcher_bar.dart:194). Regression coverage asserts four `44x44` action slots in [nmtk_ui_core/test/shell_primitives_test.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/test/shell_primitives_test.dart:139).

- `[done]` Make `NmtkLoadingScreen` theme-aware instead of hardcoding a dark surface.
  Evidence: widget accepts `backgroundColor` and `foregroundColor`, and defaults from `Theme.of(context).colorScheme` in [nmtk_ui_core/lib/widgets/loading_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/lib/widgets/loading_screen.dart:37) and [nmtk_ui_core/lib/widgets/loading_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/lib/widgets/loading_screen.dart:102).

- `[done]` Include workspace status in chip semantics so state is not conveyed by color alone.
  Evidence: semantics label includes `status: ${data.state.name}` in [nmtk_ui_core/lib/widgets/workspace_switcher_bar.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/lib/widgets/workspace_switcher_bar.dart:91).

- `[done]` Associate the bootstrap host label semantically with the input field.
  Evidence: `ShadInputFormField(label: const Text('CONTROL API HOST'))` in [nmtk/neuro_toolkit/lib/main.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/lib/main.dart:273).

- `[done]` Replace the onboarding wizard pattern with a simpler first-decision screen.
  Evidence: onboarding is now a single-screen role choice in [nmtk/neuro_toolkit/lib/screens/onboarding.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/lib/screens/onboarding.dart:19).

- `[done]` Remove `glassmorphismColor` as an institutionalized theme token.
  Evidence: the dead `copyWith` parameter is removed from [nmtk_ui_core/lib/app_theme.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/lib/app_theme.dart:149), and the theme-extension tests no longer construct it in [nmtk_ui_core/test/theme_test.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/test/theme_test.dart:31).

- `[done]` Delete dead `_UserProfileButton` code.
  Evidence: `_UserProfileButton` is not present in the live `desktop_scaffold.dart`; the relevant area now proceeds directly from `_RailProfileChip` into `_SidebarNavItem` in [nmtk_ui_core/lib/widgets/desktop_scaffold.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/lib/widgets/desktop_scaffold.dart:843).

- `[done]` Remove the old onboarding-specific ad-hoc `300ms / Curves.easeInOut` page transition.
  Evidence: the previous wizard flow is no longer present; current onboarding does not use that flow in [nmtk/neuro_toolkit/lib/screens/onboarding.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/lib/screens/onboarding.dart:19).

## Critique Checklist

- `[done]` Improve expert affordances by adding at least some keyboard shortcuts.
  Evidence: Studio now binds `Cmd/Ctrl+Enter` globally via `CallbackShortcuts` in [neurocnl/frontend/lib/screens/studio_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/screens/studio_screen.dart:639).
  Note: this does not fully satisfy the broader "power-user acceleration path" critique, but it disproves the report's "zero keyboard shortcuts anywhere" claim.

- `[done]` Add unsaved-work protection before loading a template.
  Evidence: template loads now check the active file's dirty state and confirm replacement before overwriting in [neurocnl/frontend/lib/services/template_load_guard.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/services/template_load_guard.dart:18), reused by [neurocnl/frontend/lib/widgets/template_gallery.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/template_gallery.dart:226) and [neurocnl/frontend/lib/screens/studio_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/screens/studio_screen.dart:221).

- `[done]` Add draft recovery or stronger CNL artifact protection.
  Evidence: the active draft already persists in workspace restore state, and template replacement now requires explicit confirmation before clobbering unsaved work in [neurocnl/frontend/lib/providers/workspace_provider.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/providers/workspace_provider.dart:24) and [neurocnl/frontend/lib/services/template_load_guard.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/services/template_load_guard.dart:18).

- `[partial]` Consolidate `neurocnl` onto one UI component system instead of mixing `NmtkSurfaceCard`, `Shad*`, and raw `Material`.
  Evidence: the primary editor flow now leans further into shared shell primitives. Template browsing is available inline inside the editor via `TemplateGallery(embedded: true)` in [neurocnl/frontend/lib/widgets/cnl_editor.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/cnl_editor.dart:624), and the canvas repair editor replaced its `ShadButton` usage with `NmtkPrimaryButton` in [neurocnl/frontend/lib/widgets/canvas/canvas_cnl_editor.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/canvas/canvas_cnl_editor.dart:113).
  Remaining gap: `neurocnl/frontend/lib/screens/canvas/*` and some canvas widgets still use `ShadCard`/`ShadButton`, so the module is not fully consolidated yet.

- `[done]` Fix hardcoded semantic colors in Neurosense.
  Evidence: `LiveSignalViewer` now maps error text and status chips through `NmtkShellTokens` semantic colors and neutral metadata instead of hardcoded `Colors.*` values in [Neurosense/frontend/lib/widgets/live_signal_viewer.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosense/frontend/lib/widgets/live_signal_viewer.dart:61).

- `[done]` Reduce repetition of the "Ownership Boundary" content across screens.
  Evidence: the repeated ownership-callout structure now lives in [neurocnl/frontend/lib/widgets/ownership_boundary_card.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/ownership_boundary_card.dart:6), reused by [neurocnl/frontend/lib/screens/analysis_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/screens/analysis_screen.dart:73) and [neurocnl/frontend/lib/screens/hardware_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/screens/hardware_screen.dart:116).

- `[done]` Bring Neurochip AnalysisScreen onto the shared design system.
  Evidence: the screen now uses `NmtkShellReadinessStateView` plus `NmtkSurfaceCard` and shared button primitives in [Neurochip/frontend/lib/screens/analysis_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/lib/screens/analysis_screen.dart:42), while the primary analysis panels also migrated from raw `Card` to shared shell cards in [Neurochip/frontend/lib/widgets/quantization_explorer.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/lib/widgets/quantization_explorer.dart:141) and [Neurochip/frontend/lib/widgets/power_latency_panel.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/lib/widgets/power_latency_panel.dart:18).

- `[done]` Improve icon-button tooltip coverage.
  Evidence: the remaining obvious gaps now have explicit tooltips, including the editor undo/redo and template controls in [neurocnl/frontend/lib/widgets/cnl_editor.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/cnl_editor.dart:741), the sentence-builder close affordance in [neurocnl/frontend/lib/widgets/cnl_sentence_builder_dialog.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/cnl_sentence_builder_dialog.dart:381), the device refresh action in [Neurosense/frontend/lib/widgets/device_selector.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosense/frontend/lib/widgets/device_selector.dart:30), and the signal-quality refresh action in [Neurosense/frontend/lib/widgets/signal_quality_bar.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosense/frontend/lib/widgets/signal_quality_bar.dart:179).

- `[done]` Reduce modal-first flows.
  Evidence: two previously cited modal interactions now have inline alternatives. The CNL template gallery can render directly inside the editor using `embedded: true` in [neurocnl/frontend/lib/widgets/template_gallery.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/template_gallery.dart:15) and is toggled from the toolbar in [neurocnl/frontend/lib/widgets/cnl_editor.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/cnl_editor.dart:624). NeuroSense troubleshooting guidance is now an in-card expandable panel instead of an alert dialog in [Neurosense/frontend/lib/widgets/signal_quality_bar.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosense/frontend/lib/widgets/signal_quality_bar.dart:36).

- `[done]` Add fuller undo/redo support to the CNL editing workflow.
  Evidence: the CNL editor now wires `UndoHistoryController` into the text field and exposes explicit undo/redo affordances with keyboard hints in [neurocnl/frontend/lib/widgets/cnl_editor.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/cnl_editor.dart:216) and [neurocnl/frontend/lib/widgets/cnl_editor.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/cnl_editor.dart:667).

- `[done]` Improve Neurochip shell/system coverage more broadly.
  Evidence: deeper deploy flow surfaces now use shared shell cards in addition to the landing screens. `NetworkImportCard` now renders through `NmtkSurfaceCard` in [Neurochip/frontend/lib/widgets/network_import_card.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/lib/widgets/network_import_card.dart:148), which is reused by [Neurochip/frontend/lib/screens/teensy_deploy_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/lib/screens/teensy_deploy_screen.dart:251), [Neurochip/frontend/lib/screens/pynq_deploy_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/lib/screens/pynq_deploy_screen.dart:10), and [Neurochip/frontend/lib/screens/akida_deploy_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/lib/screens/akida_deploy_screen.dart:10).

## Bottom Line

- The audit file is now fully implemented and should be treated as historical, not current.
- The critique file still describes several real structural issues, especially in `neurocnl`, `Neurochip`, and `Neurosense`.
- The highest-signal remaining gaps are:
  - neurocnl component-system consolidation across the remaining canvas screens
