# Requirements Document

## Introduction

NeuroCNL Studio today puts target selection at the very end of the workflow:
the user writes a network in the CNL editor or Canvas, runs Parse → Validate
→ Generate, then navigates to the Deploy tab, picks a target, and clicks
Run — only to discover that the target cannot execute the compiled NIR graph.
Compatibility depends entirely on the chosen target, but the target is selected
last.

This feature promotes target selection to a **first-class, always-visible**
element of the Studio workspace. A compact target chip is rendered in the
pipeline bar row (or directly above it) so the selected target is visible at
all times, regardless of which tab is active on the right panel. The chip
displays the current target name and a small compatibility status indicator
derived from the existing `nir-target-aware-preflight` preflight results. An
empty-state prompt guides users who have not yet chosen a target.

The Deploy tab and its full `_HardwareTargetRow` are unchanged and remain the
canonical place for advanced target configuration (serial port selection,
PYNQ board credentials, Akida host management, Lava/Loihi2 hardware paths).

---

## Glossary

- **Target_Chip**: The compact, always-visible widget in the Studio pipeline
  bar area that displays the currently selected deploy target name and a
  compatibility status dot. Clicking it opens the Target_Popover.
- **Target_Popover**: A lightweight inline popover (not a full dialog) that
  lists all deploy targets and lets the user switch the active one without
  navigating to the Deploy tab.
- **Compatibility_Dot**: A small circular status indicator attached to the
  Target_Chip. Green = preflight passed (exact or approximate); red = preflight
  failed (unsupported nodes); gray = no preflight result yet or preflight
  running.
- **Pipeline_Bar**: The horizontal step strip (Parse → Validate → Generate →
  Deploy) rendered at the top of the Studio's right panel workspace, currently
  implemented in `PipelineBar` / `_PipelineWorkspaceHeader`.
- **Deploy_Tab**: The Studio panel content shown when the "Deploy" step is
  selected, containing the full `_HardwareTargetRow` and all hardware-specific
  configuration UI.
- **Hardware_Target_Row**: The existing `_HardwareTargetRow` widget in
  `studio_screen.dart` that renders one `_TargetNavTile` per deploy target.
  It is NOT removed or hidden by this feature.
- **Deploy_Target**: One of the six supported targets: `lava_sim` (Lava
  simulator), `snntorch_sim` (snnTorch simulator), `teensy` (Teensy 4.1),
  `pynq` (PYNQ board), `akida` (Akida), `lava` (Lava / Loihi2 hardware).
- **Simulator_Target**: A software-only Deploy_Target: `lava_sim` or
  `snntorch_sim`.
- **Hardware_Target**: A physical-device Deploy_Target: `teensy`, `pynq`,
  `akida`, or `lava` (Loihi2).
- **Preflight_Result**: The classification result produced by the
  `Preflight_Provider` defined in the `nir-target-aware-preflight` spec:
  `level` of "exact", "approximate", or "unsupported", plus node lists and
  diagnostics.
- **Preflight_Provider**: The Riverpod provider introduced by the
  `nir-target-aware-preflight` spec that manages preflight lifecycle for a
  Simulator_Target.
- **Workspace_State**: The Riverpod `workspaceProvider` state, which owns
  `selectedDeployTarget` as a persisted field.
- **Studio_Compact**: The intentional 12 px outer padding on `StudioScreen`,
  marked with a `// studio-compact` comment; not to be increased.
- **NmtkShellTokens**: The shared design-token provider from `nmtk_ui_core`
  supplying radius, color, and spacing values.
- **AppTheme**: The module-level theme forwarding `NmtkNeurocnlTokens` values
  (`primary`, `surface`, `border`, `textPrimary`, `textSecondary`, etc.).

---

## Requirements

### Requirement 1: Persistent Target Chip in the Pipeline Bar Row

**User Story:** As a user, I want to see the currently selected deploy target
at all times while working in the Studio, so that I never lose track of which
target I am designing for.

#### Acceptance Criteria

1. THE Studio_Screen SHALL render a Target_Chip in the same horizontal row as
   the Pipeline_Bar, positioned to the left of or integrated with the existing
   `_PipelineWorkspaceHeader` widget, within the Studio content area
   (not the app bar).

2. THE Target_Chip SHALL remain visible while the user navigates between
   Parsed Specs, Validation, Generate, Compare, Deploy, and Benchmark tabs.

3. WHEN a Deploy_Target is selected, THE Target_Chip SHALL display the target's
   label (e.g. "snnTorch", "Teensy 4.1") using `AppTheme.textPrimary` for the
   label text and `AppTheme.surface` / `AppTheme.border` for its background
   and border.

4. THE Target_Chip SHALL use `NmtkShellTokens.radiusSm` (12 px) for its border
   radius, consistent with the inline-chip token from the style guide.

5. WHEN no Deploy_Target is selected, THE Target_Chip SHALL remain visible
   in the pipeline bar row and SHALL render an empty-state variant showing
   the text "Select target" in `AppTheme.textSecondary` with a dashed or
   muted border using `AppTheme.border`; the chip SHALL NOT be hidden or
   removed.

6. THE Target_Chip SHALL be rendered exclusively in the Studio content area
   (pipeline bar row) and SHALL NOT be placed in the top app bar or in any
   dual location alongside the top app bar.

---

### Requirement 2: Compatibility Dot on the Target Chip

**User Story:** As a user, I want to see at a glance whether my selected
target is compatible with my current network, so that I can fix problems early
without opening the Deploy tab.

#### Acceptance Criteria

1. WHEN a Simulator_Target is selected AND the Preflight_Provider `status` is
   `success` with `level` equal to `"exact"` or `"approximate"`, THE
   Compatibility_Dot SHALL render as a filled circle using
   `NmtkShellTokens.healthyColor` (`0xFF22C55E`).

2. WHEN a Simulator_Target is selected AND the Preflight_Provider `status` is
   `success` with `level` equal to `"unsupported"`, THE Compatibility_Dot
   SHALL render as a filled circle using `NmtkShellTokens.errorColor`
   (`0xFFEF4444`).

3. WHEN a Simulator_Target is selected AND the Preflight_Provider `status` is
   `idle` or `running`, THE Compatibility_Dot SHALL render as a filled circle
   using `AppTheme.border` (gray / muted), optionally replaced by a small
   `CircularProgressIndicator` of the same diameter while `status` is
   `running`.

4. WHEN a Hardware_Target is selected, THE Compatibility_Dot SHALL NOT be
   shown (hardware targets have no simulator preflight). WHEN no Deploy_Target
   is selected, THE Compatibility_Dot SHALL NOT be shown.

5. WHILE the UI is transitioning between Deploy_Targets (i.e.
   `selectedDeployTarget` has not yet settled to a new non-empty value),
   THE Compatibility_Dot SHALL NOT be shown, consistent with the rule that
   the dot is hidden whenever no target is currently selected.

6. THE Compatibility_Dot diameter SHALL be 8 px and SHALL be placed to the
   right of the target label text, within the Target_Chip bounds, with 6 px of
   left spacing between the label text and the dot.

---

### Requirement 3: Target Popover on Chip Click

**User Story:** As a user, I want to click the target chip and switch targets
from within the pipeline bar area, so that I can change targets without
navigating to the Deploy tab.

#### Acceptance Criteria

1. WHEN the user taps or clicks the Target_Chip, THE Studio_Screen SHALL
   display a Target_Popover anchored near the chip without covering the
   Pipeline_Bar.

2. THE Target_Popover SHALL list all six Deploy_Targets (lava_sim, snntorch_sim,
   teensy, pynq, akida, lava), each as a selectable row showing the target's
   icon and label, matching the visual style of the existing `_TargetNavTile`.

3. WHEN the user selects a target in the Target_Popover, THE
   Workspace_State's `selectedDeployTarget` SHALL be updated via
   `workspaceProvider.notifier.setSelectedDeployTarget`, and the popover SHALL
   close.

4. THE Target_Popover SHALL highlight the currently selected Deploy_Target row
   using `AppTheme.primary` tinting, consistent with the `_TargetNavTile`
   selected state.

5. WHEN the user taps outside the Target_Popover or presses Escape, THE
   Target_Popover SHALL close without changing the selected target.

6. THE Target_Popover SHALL use `NmtkShellTokens.radiusMd` (16 px) for its
   container border radius and `NmtkDesignTokens.dialogShape` SHALL NOT be
   used (the popover is not a full dialog).

7. THE Target_Popover SHALL NOT replicate the advanced hardware device
   configuration UI (serial port selector, PYNQ board list, Akida host list);
   it is a target-type selector only. A note SHALL be shown below the target
   list reading "Configure device settings in the Deploy tab."

---

### Requirement 4: Deploy Tab Retains Full Target Management UI

**User Story:** As a user, I want the Deploy tab to continue showing the full
target row and hardware configuration UI, so that I can still manage device
details from the canonical location.

#### Acceptance Criteria

1. THE Deploy_Tab SHALL continue to render the existing `_HardwareTargetRow`
   with all six `_TargetNavTile` entries unchanged.

2. THE `_HardwareTargetRow` SHALL remain the canonical surface for selecting
   hardware targets and managing per-device configuration (Teensy serial port,
   PYNQ board credentials, Akida host address, Lava/Loihi2 hardware path),
   regardless of whether the Deploy_Tab is currently rendered or visible in
   the panel page view.

3. WHEN the user changes the selected target from the Target_Popover, THE
   Deploy_Tab SHALL reflect the new selection the next time it is shown,
   because both surfaces read from the same `workspaceProvider.selectedDeployTarget`.

4. WHEN the user changes the selected target from the `_HardwareTargetRow` in
   the Deploy_Tab, THE Target_Chip SHALL immediately reflect the new selection.

5. THE Deploy_Tab SHALL NOT be hidden, removed, or reduced in functionality
   by this feature.

---

### Requirement 5: Pipeline Bar Deploy Step Links to Target Selection

**User Story:** As a user, I want the pipeline bar's Deploy step to guide me
toward target selection when no target is selected, so that the pipeline bar
is interactive and actionable rather than purely informational.

#### Acceptance Criteria

1. WHEN no Deploy_Target is selected AND the user taps the Deploy step in the
   Pipeline_Bar, THE Studio_Screen SHALL open the Target_Popover anchored
   below the Deploy step, prompting target selection.

2. WHEN a Deploy_Target is already selected AND the user taps the Deploy step
   in the Pipeline_Bar, THE Studio_Screen SHALL navigate to the Deploy tab
   (existing behaviour: `_setActivePanel('deploy')`).

3. THE Pipeline_Bar Deploy step detail text SHALL read "Select a target" when
   `workspaceProvider.selectedDeployTarget` is empty or unset, replacing the
   current generate-status-derived detail.

4. WHEN the Pipeline_Bar Deploy step displays "Select a target", THE step
   SHALL render using `NmtkStepStatus.idle` (not error), so the guidance is
   visible but not alarming.

---

### Requirement 6: Empty-State Guidance in the Pipeline Bar Area

**User Story:** As a user who has not yet chosen a target, I want to see a
gentle prompt near the pipeline bar, so that I know I need to pick a target
before running.

#### Acceptance Criteria

1. WHEN no Deploy_Target is selected, THE Target_Chip empty-state variant
   (Requirement 1.5) SHALL be visible in the pipeline bar row as the sole
   empty-state prompt; no additional banner or overlay is required.

2. THE empty-state Target_Chip SHALL be tappable and SHALL open the
   Target_Popover (Requirement 3.1), making it actionable.

4. WHEN a Deploy_Target is selected and the Target_Chip transitions from the
   empty-state variant to the normal variant, THE normal variant SHALL only
   render once `workspaceProvider.selectedDeployTarget` holds a non-empty,
   finalized target ID; intermediate states where a target interaction has
   begun but no target ID has been committed SHALL continue to show the
   empty-state variant.

5. THE empty-state prompt SHALL NOT be implemented as a blocking overlay,
   modal, full-screen dim layer, or `AlertDialog`. THE `Target_Chip`
   empty-state variant SHALL be a plain `InkWell`-wrapped container within the
   pipeline bar row, with no `Stack`, `Positioned`, or `ModalBarrier` wrapping.
   Widget tests SHALL assert that no `ModalBarrier` or overlay entry is present
   in the widget tree while the empty-state chip is showing.

---

### Requirement 7: Validation Panel Shows Target-Aware Backend Support

**User Story:** As a user with a Simulator_Target selected, I want the
Validation panel's Backend Support card to label the backend result with my
chosen target name instead of the generic "nir backend", so that I understand
which target the validation result applies to.

#### Acceptance Criteria

1. WHEN `workspaceProvider.selectedDeployTarget` is `"lava_sim"` or
   `"snntorch_sim"` AND `ValidationResult.backendSupport` is populated, THE
   `_BackendSupportCard` in `ValidationPanel` SHALL display the target's
   human-readable label (e.g. "Lava simulator", "snnTorch simulator") in place
   of the raw `support.backend` string when that string equals the selected
   target identifier.

2. WHEN the selected Deploy_Target is a Hardware_Target or no target is
   selected, THE `_BackendSupportCard` SHALL display the backend label exactly
   as it does today (no regression).

3. THE `_BackendSupportCard` subtitle SHALL read "Target: [target label] •
   [verdict]" when a Simulator_Target is active, so the validation context is
   explicit.

4. THE changes to `_BackendSupportCard` described in this requirement SHALL NOT
   affect the support verdict logic, node lists, or warning display — only the
   label text shown to the user changes.

---

### Requirement 8: Target Selection Persists Across Sessions

**User Story:** As a user, I want the Studio to remember my selected target
between sessions, so that I do not have to re-select it every time I open the
app.

#### Acceptance Criteria

1. THE selected Deploy_Target SHALL continue to be persisted in the
   `Workspace_State` JSON payload via the existing `selectedDeployTarget` field,
   and SHALL be restored when the workspace is reloaded.

2. WHEN a workspace file is opened via `_handleOpenWorkspace` and the saved
   payload contains a `selectedDeployTarget` value, THE Target_Chip SHALL
   reflect that value immediately upon load.

3. THE Target_Chip SHALL respect the existing default value of `'teensy'` for
   workspaces that were saved without a `selectedDeployTarget` field (no
   migration or breaking change to the workspace schema).

---

### Requirement 9: Target Chip Widget Tests

**User Story:** As a developer, I want widget tests for the new Target_Chip
component, so that regressions in chip rendering, dot colour, and popover
open/close are caught automatically.

#### Acceptance Criteria

1. THE test suite SHALL include a widget test verifying that the Target_Chip
   renders the target label and Compatibility_Dot with the correct colour when
   a Simulator_Target is selected and a mock Preflight_Provider returns each
   of the three `level` values ("exact", "approximate", "unsupported").

2. THE test suite SHALL include a widget test verifying that tapping the
   Target_Chip opens the Target_Popover and that selecting a target from the
   popover updates `workspaceProvider.selectedDeployTarget`.

3. THE test suite SHALL include a widget test verifying that the Target_Chip
   renders the empty-state variant when `selectedDeployTarget` is empty and
   that tapping it opens the Target_Popover.

4. THE test suite SHALL include a widget test verifying that selecting a
   Hardware_Target causes the Compatibility_Dot to be absent from the
   Target_Chip.

---

### Requirement 10: Pipeline Bar Target Indicator Integration Tests

**User Story:** As a developer, I want integration tests for the pipeline bar
target indicator state, so that the interaction between target selection,
preflight status, and the pipeline bar step text is verified end-to-end in the
widget layer.

#### Acceptance Criteria

1. THE test suite SHALL include an integration test verifying that when no
   target is selected the Pipeline_Bar Deploy step detail reads "Select a
   target" and tapping the step opens the Target_Popover.

2. THE test suite SHALL include an integration test verifying that when a
   Simulator_Target is selected and the mock Preflight_Provider returns
   `status: success` with `level: "unsupported"`, the Target_Chip
   Compatibility_Dot renders with `NmtkShellTokens.errorColor` and the
   Pipeline_Bar Deploy step reflects `StepStatus.error` (per Requirement 9.4
   of the `nir-target-aware-preflight` spec).

3. THE test suite SHALL include an integration test verifying that switching
   the selected target from the Target_Popover propagates the new value to
   both the Target_Chip label and the Deploy tab's `_HardwareTargetRow`
   selected tile, without navigating to the Deploy tab.

---

### Requirement 11: No Disruption to Hardware Deploy Paths

**User Story:** As a user targeting Teensy, PYNQ, Akida, or Lava/Loihi2
hardware, I want the hardware deploy workflow to be completely unaffected by
this feature, so that no regressions are introduced on hardware paths.

#### Acceptance Criteria

1. WHEN a Hardware_Target is selected, THE Target_Chip SHALL display the
   target label without a Compatibility_Dot (no simulator preflight is
   triggered for hardware targets).

2. THE existing Teensy `_scheduleDeployValidation` logic SHALL remain
   unchanged by this feature.

3. THE `_HardwareTargetRow`, hardware device management dialogs, and
   per-device Riverpod providers (`teensyDeployProvider`,
   `studioPynqDeployProvider`, `studioAkidaDeployProvider`,
   `studioLavaDeployProvider`) SHALL NOT be modified by this feature.

4. THE hardware deploy panels (`TeensyDeployPanel`, `PynqDeployPanel`,
   `AkidaDeployPanel`) SHALL remain unchanged and accessible from the
   Deploy_Tab exactly as today.

5. WHEN a Hardware_Target is selected and the user opens the Target_Popover,
   switching to a Simulator_Target SHALL trigger the auto-preflight schedule
   described in Requirement 4.1 of the `nir-target-aware-preflight` spec.

---

### Requirement 12: Theme and Token Compliance

**User Story:** As a developer, I want the new Target_Chip and Target_Popover
to use only the established design-token values from `AppTheme` and
`NmtkShellTokens`, so that the Studio retains visual consistency and no
non-token values are introduced.

#### Acceptance Criteria

1. THE Target_Chip and Target_Popover SHALL use only the five sanctioned
   `NmtkShellTokens` border radius values: `radiusSm` (12 px) for the chip,
   `radiusMd` (16 px) for the popover container.

2. THE Compatibility_Dot colors SHALL use only `NmtkShellTokens.healthyColor`,
   `NmtkShellTokens.errorColor`, and `AppTheme.border` for the three dot
   states (no hardcoded hex values).

3. THE Target_Chip text SHALL use `AppTheme.textPrimary` for the selected-target
   label and `AppTheme.textSecondary` for the empty-state label.

4. THE Target_Chip background and border SHALL use `AppTheme.surface` and
   `AppTheme.border` respectively, matching the `_TargetNavTile` unselected
   state palette.

5. THE Target_Chip selected state (when the chip itself is the active UI
   element, e.g. popover open) SHALL use `AppTheme.primary.withValues(alpha:
   0.14)` as background, matching the `_TargetNavTile` selected-state palette.

6. THE Studio_Screen SHALL pass `mode: NmtkShellMode.studio` to any new shell
   scaffold wrappers introduced by this feature.
