# Implementation Plan: Studio Target-First Workflow

## Overview

Promotes deploy-target selection to a first-class, always-visible element in
the Studio workspace. Introduces `TargetChip` and `TargetPopover` widgets,
extracts shared deploy-target data into a new model file, extends `PipelineBar`
with context-aware Deploy-step behaviour, and enriches the `_BackendSupportCard`
subtitle label in `ValidationPanel`.

Implementation proceeds in four waves: (1) shared data model refactor, (2) new
widget files in parallel, (3) integration into existing widgets in parallel,
(4) test files in parallel — followed by a final checkout checkpoint.

---

## Tasks

- [ ] 1. Extract deploy-target data model
  - [ ] 1.1 Create `lib/models/deploy_target.dart` with public `DeployTargetData`, `kDeployTargets`, `kSimulatorTargets`, `deployTargetForId()`, and `deployTargetLabel()` — migrate content from the private `_DeployTargetData` class and `_deployTargets` const currently in `studio_screen.dart`; make the class and helpers public
    - Define `DeployTargetData({required String id, required String label, required IconData icon})`
    - Define `const kSimulatorTargets = <String>{'lava_sim', 'snntorch_sim'}`
    - Define `const kDeployTargets` list with all six entries (lava_sim, snntorch_sim, teensy, pynq, akida, lava)
    - Implement `DeployTargetData deployTargetForId(String id)` with fallback to `kDeployTargets.first`
    - Implement `String deployTargetLabel(String id)` as a thin delegate to `deployTargetForId`
    - _Requirements: 1.3, 3.2, 12.1_

  - [ ] 1.2 Update `lib/screens/studio_screen.dart` to remove the private `_DeployTargetData` class, `_deployTargets` const, `_targetForId`, and `_targetLabel` helpers; add `import '../models/deploy_target.dart'`; replace all callsites with the new public equivalents
    - Ensure all existing `_TargetNavTile` / `_HardwareTargetRow` usages inside `studio_screen.dart` that referenced `_DeployTargetData` compile against `DeployTargetData`
    - _Requirements: 1.3, 4.1, 11.3_

- [ ] 2. Create `TargetChip` and `CompatibilityDot` widgets
  - [ ] 2.1 Create `lib/widgets/target_chip.dart` — implement `TargetChip` as a `ConsumerWidget` that reads `workspaceProvider.select((s) => s.selectedDeployTarget)` and delegates to `_TargetChipContent`
    - `_TargetChipContent` is a `ConsumerStatefulWidget`; its state (`_TargetChipContentState`) owns a nullable `OverlayEntry? _overlayEntry`
    - Empty-state variant: `GestureDetector` → muted border `Container` with "Select target" in `AppTheme.textSecondary`; no `CompatibilityDot`; no `ModalBarrier`
    - Normal-state variant: `AppTheme.surface` background, `AppTheme.border` border, `NmtkShellTokens.radiusSm` radius; label in `AppTheme.textPrimary`; active (popover-open) state uses `AppTheme.primary.withValues(alpha: 0.14)` background and `AppTheme.primary` border
    - Show `CompatibilityDot` only when `kSimulatorTargets.contains(targetId)`; 6 px `SizedBox` spacer between label and dot
    - Implement `_openPopover()` / `_closePopover()` using `Overlay.of(context).insert`; toggle semantics (second tap closes)
    - Override `dispose()` to call `_overlayEntry?.remove()`
    - Extract pure function `Color dotColorForPreflightState(PreflightState state, NmtkShellTokens tokens)` at file scope; switch on `status`/`level` per the dot-color decision table in the design
    - Extract pure function `TargetChipVariant chipVariantForTarget(String targetId)` returning `TargetChipVariant.empty` for `''` and `TargetChipVariant.normal` otherwise (define the enum in the same file)
    - _Requirements: 1.1, 1.3, 1.4, 1.5, 2.4, 2.6, 6.1, 6.2, 6.4, 6.5, 12.1, 12.3, 12.4, 12.5_

  - [ ] 2.2 Implement `CompatibilityDot` as a `ConsumerWidget` inside `lib/widgets/target_chip.dart`
    - Read `ref.watch(preflightProvider)` and call `dotColorForPreflightState` to determine color
    - Render 8 × 8 px `BoxShape.circle` container; substitute a same-size `CircularProgressIndicator(strokeWidth: 1.5)` when `status` is `running`
    - Use only `NmtkShellTokens.healthyColor`, `NmtkShellTokens.errorColor`, and `AppTheme.border` for dot color (no hardcoded hex)
    - _Requirements: 2.1, 2.2, 2.3, 2.6, 12.2_

- [ ] 3. Create `TargetPopover` widget
  - [ ] 3.1 Create `lib/widgets/target_popover.dart` — implement `TargetPopover` as a `ConsumerWidget` accepting `anchorOffset`, `anchorSize`, `onClose`, and `onSelectTarget` parameters
    - Use a `Stack` with `Positioned.fill` transparent `GestureDetector` (dismiss layer, `HitTestBehavior.translucent`) and a `Positioned` popover container anchored at `anchorOffset.dy + anchorSize.height + 4`; add edge-clamp using `MediaQuery.of(context).size.height`
    - Wrap the container in a `KeyboardListener` that calls `onClose()` on `LogicalKeyboardKey.escape`
    - `Material` container: `AppTheme.surface` color, `NmtkShellTokens.radiusMd` border radius, elevation 8, `AppTheme.border` border, width 220
    - Render `_PopoverTargetRow` for each of the six entries in `kDeployTargets`; read `workspaceProvider.select((s) => s.selectedDeployTarget)` to determine which row is selected
    - `_PopoverTargetRow` highlights the selected row with `AppTheme.primary.withValues(alpha: 0.14)` background and `AppTheme.primary` foreground; unselected rows use `AppTheme.textPrimary`
    - Show a `Divider` followed by a "Configure device settings in the Deploy tab." footer note
    - Do NOT use `showDialog`, `ModalBarrier`, or `NmtkDesignTokens.dialogShape`
    - _Requirements: 3.1, 3.2, 3.4, 3.5, 3.6, 3.7, 6.5, 12.1_

- [ ] 4. Integrate `TargetChip` into `_PipelineWorkspaceHeader`
  - [ ] 4.1 Modify `_PipelineWorkspaceHeader.build` in `lib/screens/studio_screen.dart` — insert `const TargetChip()` (keyed with `_targetChipKey = GlobalKey(debugLabel: 'target-chip')`) between the play/stop button `SizedBox` gap and the `Expanded(PipelineBar(...))`, add a second `SizedBox(width: gap)` after the chip; import `target_chip.dart`
    - Add `_handleDeployStepTap(BuildContext context, WidgetRef ref)` method: when `selectedDeployTarget.isEmpty`, access `_targetChipKey.currentState as _TargetChipContentState?` and call `._openPopover()`; otherwise call `onSelected('deploy')`
    - Pass `onDeployStepTapped: () => _handleDeployStepTap(context, ref)` to `PipelineBar`
    - _Requirements: 1.1, 1.2, 1.6, 5.1, 5.2_

- [ ] 5. Extend `PipelineBar` with context-aware Deploy step
  - [ ] 5.1 Modify `lib/widgets/pipeline_bar.dart` — add optional `VoidCallback? onDeployStepTapped` constructor parameter; read `workspaceProvider.select((s) => s.selectedDeployTarget)` inside `build`; when `noTarget` is true, set the Deploy step `detail` to `'Select a target'` and `status` to `NmtkStepStatus.idle` and pass `onTap: onDeployStepTapped`
    - Extract `String? deployDetailFor({required PipelineState pipeline, required String selectedTarget})` as a pure function at file scope: returns `'Select a target'` when `selectedTarget.isEmpty`, otherwise existing generate-status logic
    - Extract `NmtkStepStatus deployStatusFor({required PipelineState pipeline, required String selectedTarget})` as a pure function at file scope: returns `NmtkStepStatus.idle` when `selectedTarget.isEmpty`, otherwise existing status-mapping logic
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [ ] 6. Enrich `_BackendSupportCard` in `ValidationPanel`
  - [ ] 6.1 Modify `lib/widgets/validation_panel.dart` — change `_BackendSupportCard` from `StatelessWidget` to `ConsumerWidget`; read `workspaceProvider.select((s) => s.selectedDeployTarget)`; build the subtitle as `'Target: $displayBackend • ${support.verdict}'` when `selectedTarget` is a simulator key and `support.backend == selectedTarget`, otherwise keep the existing label exactly
    - Extract `String backendDisplayLabel(String supportBackend, String selectedTarget)` as a pure function at file scope using the `{'lava_sim': 'Lava simulator', 'snntorch_sim': 'snnTorch simulator'}` map
    - No changes to verdict logic, node lists, or warning display
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

- [ ] 7. Checkpoint — verify integration compiles
  - Ensure all modified and new files compile without errors: run `flutter analyze` in `neurocnl/frontend`; fix any import cycles, unused imports, or type errors before proceeding to test tasks.

- [ ] 8. Write `TargetChip` widget tests
  - [ ]* 8.1 Create `test/widgets/target_chip_test.dart` — empty-state tests: assert "Select target" text present, `CompatibilityDot` absent, `ModalBarrier` absent; assert tapping opens `TargetPopover`
    - Override `workspaceProvider` with `selectedDeployTarget: ''` and `preflightProvider` with idle state
    - _Requirements: 9.3, 6.5_

  - [ ]* 8.2 Create (extend same file) — simulator-target dot-state tests for `lava_sim` and `snntorch_sim` × three `level` values (`exact` → green, `approximate` → green, `unsupported` → red) and `idle` → gray, covering all combinations in the dot-color table
    - Override `workspaceProvider` with simulator target; override `preflightProvider` with the appropriate `PreflightState`
    - Assert `CompatibilityDot` container decoration color equals `const Color(0xFF22C55E)` or `const Color(0xFFEF4444)` or `AppTheme.border`
    - _Requirements: 9.1, 2.1, 2.2, 2.3_

  - [ ]* 8.3 Create (extend same file) — hardware-target tests for all four hardware IDs (`teensy`, `pynq`, `akida`, `lava`): assert `CompatibilityDot` not present, target label is present
    - _Requirements: 9.4, 2.4, 11.1_

  - [ ]* 8.4 Create (extend same file) — popover open/close tests: tapping chip opens `TargetPopover`; tapping a target row in the popover updates `workspaceProvider.selectedDeployTarget` and removes `TargetPopover` from tree
    - _Requirements: 9.2, 3.3, 4.3_

- [ ] 9. Write `TargetPopover` widget tests
  - [ ]* 9.1 Create `test/widgets/target_popover_test.dart` — assert all six target labels listed when popover opens; assert selected row has `AppTheme.primary.withValues(alpha: 0.14)` tinting; assert no `ModalBarrier` present
    - _Requirements: 3.2, 3.4, 6.5_

  - [ ]* 9.2 Create (extend same file) — dismiss-layer tests: tapping outside the popover closes it without changing selection; Escape key closes popover without changing selection
    - _Requirements: 3.5_

  - [ ]* 9.3 Create (extend same file) — selection test: tapping a non-selected row calls `onSelectTarget` with the correct ID and removes the popover from the widget tree
    - _Requirements: 3.3, 4.4_

- [ ] 10. Write pipeline-bar integration tests
  - [ ]* 10.1 Create `test/screens/studio_pipeline_bar_test.dart` — "Select a target" scenario: pump with `selectedDeployTarget: ''`; assert Deploy step detail text is `'Select a target'`; tap Deploy step; assert `TargetPopover` appears in overlay (no panel navigation)
    - _Requirements: 10.1, 5.1, 5.3, 5.4_

  - [ ]* 10.2 Create (extend same file) — target-selected scenario: pump with `selectedDeployTarget: 'snntorch_sim'`; tap Deploy step; assert active panel changed to `'deploy'`; assert `TargetPopover` absent
    - _Requirements: 5.2_

  - [ ]* 10.3 Create (extend same file) — cross-surface propagation test: pump with `selectedDeployTarget: 'teensy'`; open `TargetChip` popover; tap `snnTorch` row; assert `TargetChip` label updates to `'snnTorch'`; navigate to Deploy tab; assert `snntorch_sim` `_TargetNavTile` has selected (primary-tinted) state
    - _Requirements: 10.3, 4.3, 4.4_

- [ ] 11. Write property-based tests for pure functions
  - [ ]* 11.1 Create `test/logic/target_chip_properties_test.dart` — **Property 1**: enumerate all `PreflightStatus` × `level` combinations for `dotColorForPreflightState`; assert `healthyColor` for `exact`/`approximate`, `errorColor` for `unsupported` or `error`, `AppTheme.border` for `idle`/`running`
    - **Property 1: CompatibilityDot color reflects preflight level for any simulator target**
    - **Validates: Requirements 2.1, 2.2, 2.3**

  - [ ]* 11.2 Create (extend same file) — **Property 5**: enumerate empty and non-empty `selectedDeployTarget` across representative `PipelineState` variants for `deployDetailFor` and `deployStatusFor`; assert `'Select a target'` / `NmtkStepStatus.idle` for empty target, existing-logic results for non-empty
    - **Property 5: Deploy step detail is "Select a target" iff selectedDeployTarget is empty**
    - **Validates: Requirements 5.3, 5.4**

  - [ ]* 11.3 Create (extend same file) — **Property 6**: enumerate all six `kDeployTargets` IDs plus empty string for `chipVariantForTarget`; assert `TargetChipVariant.normal` for any non-empty valid ID, `TargetChipVariant.empty` for `''`
    - **Property 6: Chip variant matches selectedDeployTarget non-emptiness**
    - **Validates: Requirements 1.3, 1.5, 6.4**

  - [ ]* 11.4 Create (extend same file) — **Property 7**: enumerate all combinations of `supportBackend` × `selectedTarget` for `backendDisplayLabel`; assert human-readable labels for the two simulator keys when `supportBackend == selectedTarget`, raw pass-through otherwise
    - **Property 7: _BackendSupportCard subtitle label for simulator targets**
    - **Validates: Requirements 7.1, 7.2, 7.3**

  - [ ]* 11.5 Create (extend same file) — **Property 8**: enumerate all six valid target IDs for `WorkspaceState.toJson()` / `WorkspaceState.fromJson()`; assert `selectedDeployTarget` survives the round-trip; also assert fallback to `'teensy'` when field is absent from JSON
    - **Property 8: Target selection persists across workspace serialization round-trip**
    - **Validates: Requirements 8.1, 8.2, 8.3**

- [ ] 12. Final checkpoint — full test suite
  - Run `flutter test` in `neurocnl/frontend`; all tests must pass. Run `flutter analyze` in `neurocnl/frontend`; zero errors or warnings.

---

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP.
- Each task references specific requirements for traceability.
- Pure functions (`dotColorForPreflightState`, `deployDetailFor`, `deployStatusFor`, `backendDisplayLabel`, `chipVariantForTarget`) must be extracted as top-level file-scope functions so they are directly importable in `test/logic/target_chip_properties_test.dart` without pumping a widget.
- `_TargetChipContentState._openPopover()` is accessed from `_PipelineWorkspaceHeader` via `GlobalKey`; this is idiomatic Flutter for same-subtree state access. If fragile in testing, expose a `TargetChipController` wrapper.
- The `OverlayEntry` dismiss layer uses `HitTestBehavior.translucent` — tests must pump the overlay to assert it is present/absent.
- No new Riverpod providers are introduced; `preflightProvider` is owned by the `nir-target-aware-preflight` spec and should be overridden in tests.
- `_HardwareTargetRow`, all hardware device providers, and all hardware deploy panels remain completely unchanged.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2"] },
    { "id": 2, "tasks": ["2.1", "2.2", "3.1"] },
    { "id": 3, "tasks": ["4.1", "5.1", "6.1"] },
    { "id": 4, "tasks": ["8.1", "8.2", "8.3", "8.4", "9.1", "9.2", "9.3", "10.1", "10.2", "10.3", "11.1", "11.2", "11.3", "11.4", "11.5"] }
  ]
}
```
