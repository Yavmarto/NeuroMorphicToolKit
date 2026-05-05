# Auto-Aligning Pipeline Strip Primitive

## Owner

- `M2` Single-repo cloud agent or local module owner

## Depends on

- `nmtk_ui_core/issues/01-shell-tokens-top-bars-and-status-primitives.md`
- `neurocnl/issues/14-neurostudio-run-sim-play-button.md`

## Can run in parallel with

- `neurocnl/issues/15-neurostudio-pipeline-pane-responsive-audit.md`

## Write scope

- `nmtk_ui_core/lib/widgets/`
- `nmtk_ui_core/lib/nmtk_ui_core.dart`
- `nmtk_ui_core/test/`
- consumer follow-up call sites only if extraction requires them

## Background

`neurocnl/frontend/lib/widgets/pipeline_bar.dart` now contains useful shell behavior that is not
really `neurocnl`-specific:

- horizontally scrollable pipeline steps
- controlled active-step selection
- automatic left-edge alignment of the selected step
- responsive use inside compact toolbars

That behavior will likely be needed again in other suite modules that expose multi-stage workflows.
Right now it lives as module-local code, which risks drift if another module reimplements the same
pattern differently.

## Tasks

- Design a shared `nmtk_ui_core` pipeline strip widget that supports:
  - horizontal scrolling
  - selected-step highlighting
  - optional status icons or running indicators
  - programmatic active-step alignment to the leading edge
  - callback-based selection
- Keep the shared widget state-management-agnostic; no Riverpod or module-specific providers.
- Define a small typed data model for steps if the existing `NmtkPipelineStepData` is too limited.
- Add widget tests covering:
  - initial active step render
  - selection callback
  - auto-scroll to selected step
  - compact-width behavior
- Migrate `neurocnl` to the shared primitive once the API is stable, or document why the shared
  extraction should wait.

## Done when

- `nmtk_ui_core` exposes a reusable pipeline strip primitive with active-step auto-alignment.
- The API is typed and consumer-safe without importing module-specific code.
- The widget is covered by `nmtk_ui_core` tests.
- At least one real consumer path is proven, either by migrating `neurocnl` or by validating the
  API against its current `PipelineBar` requirements.

## Validation

- `cd nmtk_ui_core && flutter test`
- If migrated immediately: `cd neurocnl/frontend && flutter test`
- Manual: verify the active step animates into view and lands at the left edge when selected from a
  partially off-screen position.
