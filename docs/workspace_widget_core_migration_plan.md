# Operational Workspace Widget Migration Plan

## Purpose

Define how to move reusable operational workspace widgets out of a single product module and into `nmtk_ui_core` so every frontend in the monorepo can share the same shell, card, and workflow primitives.

This document is the canonical repo-level migration plan. It replaces the earlier Neurochip-local deployment widget plan and should be used by any agent working on shared workspace UI.

## Scope

The target pattern is any operational screen that combines:

- a primary authoring or configuration area
- a secondary status, workflow, or action area
- shared cards for overview, progress, results, errors, or summaries

This includes deployment, export, runtime preparation, benchmarking, verification, and similar workflows.

## Why This Belongs In `nmtk_ui_core`

- The layout and card primitives are structural UI concerns, not module-specific business logic.
- Multiple modules already need the same two-pane workspace pattern.
- `nmtk_ui_core` is the right package for shared, presentation-focused Flutter widgets that must stay independent of module state and services.
- Keeping these widgets in one product module leads to copy-paste reuse instead of API reuse.

## Design Constraints

The migration must preserve `nmtk_ui_core` package boundaries:

- No Riverpod, Provider, routing, service, backend-client, or module imports.
- Widgets must stay callback-based and state-management-agnostic.
- Public APIs must use generic names that fit deployment, export, runtime, benchmark, and verification flows equally well.
- Shared models, enums, and constructor shapes must be presentation-oriented rather than contract- or provider-oriented.
- Public widgets must be exported intentionally from `nmtk_ui_core/lib/nmtk_ui_core.dart`.

## Current State

### Canonical Seed Implementation

The initial extraction source is:

- `Neurochip/frontend/lib/widgets/deploy_workspace.dart`

It currently defines the reusable patterns that should be generalized:

- `DeployWorkspaceShell`
- `DeployWorkspaceOverviewCard`
- `DeployInfoChip`
- `DeployWorkflowCard`
- `DeployWorkflowStage`
- `DeployWorkflowStageState`
- `DeploySectionCard`
- `DeployResultCard`
- `DeployProgressCard`
- `DeployErrorCard`
- `DeployTargetSummaryCard`

These names are implementation history, not the target public API.

### Existing Cross-Module Duplication

The following module-local implementations overlap with the same structural pattern and should be treated as explicit migration targets rather than abstract future possibilities:

- `Neurobench/frontend/lib/screens/workbench_shell.dart`
  uses a workbench shell pattern analogous to the shared two-pane workspace shell
- `Neurohub/frontend/lib/widgets/workflow_step_card.dart`
  overlaps with the workflow card and stage presentation pattern
- `Neurohub/frontend/lib/widgets/milestone_timeline.dart`
  overlaps with shared stage and workflow-state rendering concerns
- `neurocnl/frontend/lib/screens/deploy_screen.dart`
  is the primary second adopter because it already hosts a broad multi-target operational workflow and is the clearest non-Neurochip consumer

## Target Architecture

### `nmtk_ui_core` Should Own

- responsive two-pane workspace shell
- overview card with optional supporting chips and message body
- generic info chip
- workflow card with stage model and stage-state enum
- section framing card
- progress/status card for determinate and indeterminate states
- result card for success, warning, or neutral outcomes
- error card with selectable text and optional action affordances
- summary card for compact title, description, and chip groups

### Consumer Modules Should Own

- provider or Riverpod state
- service calls and backend response handling
- module-specific validation and explanatory copy
- domain-specific forms and action controls
- contract-derived models and any adapters from domain state into shared widget inputs
- widgets that encode semantics unique to one module or one hardware/runtime path

## Target Public API

The shared widgets should use domain-neutral names:

| Seed implementation name | Shared `nmtk_ui_core` name |
|---|---|
| `DeployWorkspaceShell` | `NmtkWorkspaceShell` |
| `DeployWorkspaceOverviewCard` | `NmtkWorkspaceOverviewCard` |
| `DeployInfoChip` | `NmtkInfoChip` |
| `DeployWorkflowCard` | `NmtkWorkflowCard` |
| `DeployWorkflowStage` | `NmtkWorkflowStage` |
| `DeployWorkflowStageState` | `NmtkWorkflowStageState` |
| `DeploySectionCard` | `NmtkSectionCard` |
| `DeployResultCard` | `NmtkResultCard` |
| `DeployProgressCard` | `NmtkProgressCard` |
| `DeployErrorCard` | `NmtkErrorCard` |
| `DeployTargetSummaryCard` | `NmtkSummaryCard` |

`Deploy` should not appear in the shared API because the components are intended for more than deployment flows.

## Reuse Rules

Move a widget into `nmtk_ui_core` only if it satisfies all of the following:

- It expresses layout or presentation structure rather than domain behavior.
- Its inputs can be reduced to plain Dart and Flutter types, simple enums, or child widgets.
- At least one additional module can plausibly consume it without adapter-heavy API design.
- Its naming remains coherent outside the source module that originally introduced it.

Keep a widget in the owning module if any of the following is true:

- It depends on one module's backend payloads or hardware semantics.
- It is tightly coupled to a single deploy/export/runtime path.
- It requires provider-owned or service-owned state to render correctly.
- Reuse would force other modules to adopt vocabulary that is wrong for their domain.

## Migration Strategy

### Phase 1: Extract Shared Structural Widgets

Primary write set:

- `nmtk_ui_core/lib/widgets/`
- `nmtk_ui_core/lib/nmtk_ui_core.dart`
- the source module widget file that currently owns the implementation
- the source module screens that consume those widgets

Steps:

1. Copy only the structural, presentation-oriented widgets into `nmtk_ui_core`.
2. Rename them to the generic `Nmtk*` API.
3. Remove module-specific wording, assumptions, and constructor parameters from the extracted widgets.
4. Export them from the core barrel.
5. Switch the source module to the shared imports.
6. Delete the duplicated local implementations once the source module compiles against the shared versions.

Acceptance:

- The source module uses `nmtk_ui_core` for the shared shell and card primitives.
- No module-specific state or service dependency is introduced into `nmtk_ui_core`.

### Phase 1 Implementation Plan

#### Goal

Complete a seed extraction from `Neurochip/frontend/lib/widgets/deploy_workspace.dart` into `nmtk_ui_core` without changing workflow behavior in the three existing Neurochip deployment screens.

#### Phase 1 Write Set

- `nmtk_ui_core/lib/widgets/`
- `nmtk_ui_core/lib/nmtk_ui_core.dart`
- `Neurochip/frontend/lib/widgets/deploy_workspace.dart`
- `Neurochip/frontend/lib/screens/pynq_deploy_screen.dart`
- `Neurochip/frontend/lib/screens/teensy_deploy_screen.dart`
- `Neurochip/frontend/lib/screens/akida_deploy_screen.dart`

#### Implementation Sequence

1. Audit the seed widget file and separate structural widgets from any module-specific wrappers or vocabulary that must stay local.
2. Create shared widget files in `nmtk_ui_core/lib/widgets/` for the reusable workspace shell, overview, chip, workflow, section, result, progress, error, and summary primitives.
3. Rename the public types to the `Nmtk*` API and normalize constructor names so they read correctly outside deployment flows.
4. Export the new shared models and widgets from `nmtk_ui_core/lib/nmtk_ui_core.dart`.
5. Update Neurochip deploy screens to import the shared barrel and migrate all call sites from `Deploy*` names to `Nmtk*` names.
6. Reduce `Neurochip/frontend/lib/widgets/deploy_workspace.dart` to either a compatibility shim or delete it entirely once all local references are removed.
7. Run the shared-package and Neurochip frontend checks before treating the extraction as complete.

#### Extraction Breakdown

Move these types into `nmtk_ui_core` during Phase 1:

- `DeployWorkspaceShell` -> `NmtkWorkspaceShell`
- `DeployWorkspaceOverviewCard` -> `NmtkWorkspaceOverviewCard`
- `DeployInfoChip` -> `NmtkInfoChip`
- `DeployWorkflowCard` -> `NmtkWorkflowCard`
- `DeployWorkflowStage` -> `NmtkWorkflowStage`
- `DeployWorkflowStageState` -> `NmtkWorkflowStageState`
- `DeploySectionCard` -> `NmtkSectionCard`
- `DeployResultCard` -> `NmtkResultCard`
- `DeployProgressCard` -> `NmtkProgressCard`
- `DeployErrorCard` -> `NmtkErrorCard`
- `DeployTargetSummaryCard` -> `NmtkSummaryCard`

Keep these concerns in Neurochip during Phase 1:

- mapping deploy state into `NmtkWorkflowStageState`
- any target-specific copy, icons, validation, and action wiring in the deploy screens
- any domain-specific helper methods that derive progress, support state, or result text from Neurochip models

#### Shared API Shaping Rules

Apply these API changes while extracting:

- rename `message` or `description` fields only when the new name is clearly more generic; avoid churn that does not improve reuse
- keep inputs limited to Flutter primitives, `Widget`, `IconData`, `Color`, `NmtkTone`, and small shared enums or data classes
- do not introduce package imports beyond Flutter and existing `nmtk_ui_core` dependencies
- preserve composability by keeping optional `leading`, `trailing`, `prefix`, `chips`, and `details` slots as widget-based extension points
- prefer constructor defaults that preserve current Neurochip behavior so screen migrations stay mechanical

#### Suggested File Layout In `nmtk_ui_core`

Use one focused file per public widget or tightly related model group:

- `widgets/workspace_shell.dart`
- `widgets/workspace_overview_card.dart`
- `widgets/info_chip.dart`
- `widgets/workflow_card.dart`
- `widgets/section_card.dart`
- `widgets/result_card.dart`
- `widgets/progress_card.dart`
- `widgets/error_card.dart`
- `widgets/summary_card.dart`

If the workflow model and widget stay closely coupled, keep `NmtkWorkflowStage` and `NmtkWorkflowStageState` in `widgets/workflow_card.dart` for Phase 1 rather than creating a separate model file prematurely.

#### Screen Migration Order

Migrate Neurochip consumers in this order:

1. `pynq_deploy_screen.dart`
2. `teensy_deploy_screen.dart`
3. `akida_deploy_screen.dart`

This order keeps the first pass on the simplest deploy screens before the larger Akida surface, which is the highest-risk adopter inside the seed module.

#### Verification Plan

Run these checks for Phase 1:

- `cd nmtk_ui_core && flutter test`
- `cd Neurochip/frontend && flutter test`

Review these outcomes before closing Phase 1:

- all Neurochip deploy screens compile against `package:nmtk_ui_core/nmtk_ui_core.dart`
- no shared widget imports `provider`, `flutter_riverpod`, service code, or module-local files
- the public barrel exports every new `Nmtk*` type introduced by the extraction
- no remaining screen in Neurochip depends on the old `Deploy*` widget classes unless an intentional short-lived compatibility shim is documented

#### Definition Of Done

Phase 1 is complete when all of the following are true:

- the reusable deploy workspace primitives live in `nmtk_ui_core`
- Neurochip uses the shared `Nmtk*` widgets instead of local `Deploy*` implementations
- the extraction preserves current screen behavior and layout semantics
- the shared API is domain-neutral enough for `neurocnl` to adopt in Phase 3 without a second rename pass

### Phase 2: Stabilize The Shared API With Tests

Test focus:

- split versus stacked layout behavior in `NmtkWorkspaceShell`
- overview card chip and message rendering in `NmtkWorkspaceOverviewCard`
- workflow stage rendering for each `NmtkWorkflowStageState` in `NmtkWorkflowCard`
- determinate versus indeterminate behavior in `NmtkProgressCard`
- selectable-text and action-button modes in `NmtkErrorCard`
- tone handling in `NmtkSectionCard` and `NmtkResultCard`

Acceptance:

- `nmtk_ui_core` has direct widget coverage for the shared components.
- Constructor shapes and naming are stable enough for adoption by other modules.

### Phase 2 Implementation Plan

#### Goal

Add direct widget coverage for the Phase 1 workspace primitives in `nmtk_ui_core` so the shared API is stable before a second module adopts it.

#### Phase 2 Write Set

- `nmtk_ui_core/test/`
- `nmtk_ui_core/lib/widgets/` only if a test exposes a real API or rendering defect
- `nmtk_ui_core/lib/nmtk_ui_core.dart` only if a missing public export is discovered during test authoring

#### Test File Strategy

Keep the new coverage in focused shared-package tests rather than relying on downstream module tests:

- extend `nmtk_ui_core/test/shared_shell_widgets_test.dart` for card-level primitives that match the existing shell-widget test pattern
- add `nmtk_ui_core/test/workspace_shell_test.dart` for split and stacked layout behavior
- add `nmtk_ui_core/test/workflow_card_test.dart` if workflow-state permutations become too large for `shared_shell_widgets_test.dart`

Do not place Phase 2 coverage in Neurochip tests because the point of this phase is to verify the shared library directly.

#### Coverage Matrix

Add test cases for the following behaviors:

- `NmtkWorkspaceShell`
  verify split layout above the breakpoint
  verify stacked layout below the breakpoint
  verify `layoutId` keys remain present for layout, left pane, and right pane lookup
- `NmtkWorkspaceOverviewCard`
  verify title, subtitle, message, and trailing content render
  verify chips render when provided and disappear cleanly when omitted
- `NmtkInfoChip`
  verify the composed `label: value` text renders correctly
  verify the icon is present
- `NmtkWorkflowCard`
  verify one tile renders per stage
  verify all `NmtkWorkflowStageState` values map to the expected icon family and visible text
  verify default title and subtitle still render
- `NmtkSectionCard`
  verify neutral and non-neutral tones render through `NmtkSurfaceCard` without dropping header content
  verify optional leading and trailing widgets render
- `NmtkResultCard`
  verify it wraps `NmtkSectionCard` semantics correctly for success and warning-style use
- `NmtkProgressCard`
  verify determinate mode uses the provided value
  verify indeterminate mode renders when `progress` is null
  verify `errorText` switches the text color path and keeps details visible
- `NmtkErrorCard`
  verify plain text mode
  verify selectable text mode
  verify optional prefix and trailing action render
- `NmtkSummaryCard`
  verify title, description, and chip list render together

#### Test Data And Harness Rules

Use lightweight widget harnesses only:

- wrap test subjects in `MaterialApp` and `Scaffold` when needed for theme and layout
- use plain `SizedBox`, `Text`, and `Icon` fixtures for `leading`, `trailing`, `prefix`, `chips`, and `details`
- keep assertions on public behavior such as visible text, keys, icons, and widget presence rather than implementation-private padding or decoration internals

#### Stabilization Rules During Phase 2

If a test reveals an issue, limit fixes to one of these categories:

- missing export from `nmtk_ui_core.dart`
- constructor default that is internally inconsistent
- rendering bug that blocks generic reuse
- obviously deploy-specific copy that survived Phase 1

Do not use Phase 2 as an excuse to redesign the API unless the current surface is demonstrably blocking reuse or testability.

#### Verification Plan

Run these checks for Phase 2:

- `cd nmtk_ui_core && flutter test`
- `cd Neurochip/frontend && flutter test`

The Neurochip run remains part of the phase because it confirms the new shared tests did not require breaking API churn in the first adopter.

#### Definition Of Done

Phase 2 is complete when all of the following are true:

- every Phase 1 shared workspace primitive has direct coverage in `nmtk_ui_core`
- the tests exercise both default paths and key optional rendering branches
- no downstream module is required to test the shared widgets' basic behavior
- the shared API remains unchanged or changes only in narrowly justified, additive ways

### Phase 3: Adopt In Additional Modules

Primary second adopter:

- `neurocnl/frontend/lib/screens/deploy_screen.dart`

Additional adopters include:

- `Neurobench` operational workspaces
- `Neurohub` workflow or milestone surfaces
- `Neurosim` export or verification screens
- `nmtk` launcher workflows when the same structural pattern applies

Adoption rule:

- Replace only duplicated shell and card primitives first.
- Keep module-specific panels, forms, charts, timelines, and hardware-specific status components in the owning module.

Acceptance per adopting module:

- The module imports shared widgets only from `package:nmtk_ui_core/nmtk_ui_core.dart`.
- No module imports private widget code from another product module.
- The owning frontend checks pass.

### Phase 4: Audit For Secondary Extractions

After multiple consumers exist, audit the next extraction candidates explicitly:

- `neurocnl/frontend/lib/screens/deploy_screen.dart`
  confirm the first adoption extracted only shell and card primitives, then identify any repeated secondary patterns worth sharing
- `Neurobench/frontend/lib/screens/workbench_shell.dart`
  check whether the workbench shell still carries reusable secondary frame components after the first shell migration
- `Neurohub/frontend/lib/widgets/workflow_step_card.dart`
  evaluate whether its remaining workflow metadata layout belongs in shared UI
- `Neurohub/frontend/lib/widgets/milestone_timeline.dart`
  evaluate whether timeline or milestone presentation is truly generic enough to move
- support-state cards
- action clusters
- summary layouts with repeated chip and metadata patterns

Do not extract these by default. They should move only after reuse is demonstrated across real consumers.

## What Should Not Move Yet

- hardware-specific support-state cards
- target-specific empty states
- backend-payload-specific result widgets
- contract-derived typed models that are not already shared
- module-specific action clusters whose button semantics differ materially across modules
- charts, tables, timelines, or forms that are specific to one workflow domain

## Risks

### Risk 1: Premature Generalization

If the shared API is shaped too tightly around the seed implementation, later consumers will need awkward adapters.

Mitigation:

- keep the shared layer structural
- prefer plain strings, enums, icons, and child widgets
- reject module vocabulary in public APIs

### Risk 2: Shared Package Bloat

If every visually similar widget moves into `nmtk_ui_core`, the package becomes a dumping ground instead of a stable design layer.

Mitigation:

- require demonstrated or clearly plausible reuse
- keep domain behavior in the owning module
- extract in small layers rather than large wholesale moves

### Risk 3: Cross-Module API Churn

Once multiple modules adopt these widgets, constructor changes become cross-module work.

Mitigation:

- stabilize naming before broad adoption
- add widget tests before expanding consumers
- prefer additive API changes over breaking renames

## Recommended Implementation Order

1. Extract the current shared structural widgets from the seed module into `nmtk_ui_core`.
2. Rename them to the generic `Nmtk*` API and export them from the core barrel.
3. Migrate the seed module to the shared imports and delete local duplicates.
4. Add `nmtk_ui_core` widget tests.
5. Adopt the shared widgets in the next module with the clearest duplicate pattern.
6. Repeat module adoption incrementally, auditing for real reuse before extracting more.

## Validation Checklist

For `nmtk_ui_core`:

- `flutter analyze`
- `flutter test`

For the seed module:

- `Neurochip/frontend`: run `flutter analyze`
- `Neurochip/frontend`: run `flutter test`

For primary and additional adopters:

- `neurocnl/frontend`: run `flutter analyze`
- `neurocnl/frontend`: run `flutter test`
- `Neurobench/frontend`: run `flutter analyze`
- `Neurobench/frontend`: run `flutter test`
- `Neurohub/frontend`: run `flutter analyze`
- `Neurohub/frontend`: run `flutter test`

For cross-module integrity:

- verify no module imports private widget code from another module
- run `python3 -m pytest tests/integration/test_cross_module.py` if the change crosses a suite-visible contract boundary

## Definition Of Done

This migration is complete when:

- the shared workspace shell and card primitives live in `nmtk_ui_core`
- the public API uses generic `Nmtk*` naming rather than deploy-specific naming
- the seed module uses only the shared versions for the extracted widgets
- at least one additional module adopts the shared widgets without copying source-module code
- the shared widgets have direct tests in `nmtk_ui_core`
- there is a single canonical repo-level migration document for this work

## Follow-Up Work

- add screenshot or golden tests if the shared widgets become visually critical
- audit whether support-state widgets can converge after at least two real consumers exist
- consider a second shared layer for action clusters or metadata summaries only after repeated reuse is visible
