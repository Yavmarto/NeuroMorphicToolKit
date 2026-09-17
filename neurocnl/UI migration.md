# UI Core Consolidation Plan

This plan outlines the steps to centralize the UI theme, design tokens, and shared components for all submodules into the root `nmtk_ui_core` package. This will eliminate cross-module code duplication, ensure a consistent brand identity, and simplify maintenance.

## User Review Required

> [!IMPORTANT]
> **Theme Harmonization**: Currently, submodules like `neurocnl` use a specific "Purple/Lavender" theme, while the root `nmtk_ui_core` uses an "NMTK Navy/Blue" theme. I propose extending the root `AppTheme` to support "Brand Variants" so each submodule can maintain its identity while sharing the same underlying design logic.

Answer: Answer: It should look as if it's from the same suite, so like microsoft and apple both have their own unified look for their office suite

## Proposed Changes

### [Component] Root UI Core (nmtk_ui_core)

The root `nmtk_ui_core` will be enhanced to serve as the single source of truth for the entire NMTK suite.

#### [MODIFY] [app_theme.dart](file:///NeuroMorphicToolKit/nmtk_ui_core/lib/app_theme.dart)

- Update `AppTheme` to accept configuration for "Module-Specific" styles (e.g., `themeVariant: NmtkThemeVariant.neurocnl`).
- Centralize syntax highlighting colors used by different modules (e.g., `synKeyword`, `synSubject`).
- Move the design tokens from `neurocnl` and others into centralized `NmtkDesignTokens`.

#### [NEW] [Shared Widgets](file:///NeuroMorphicToolKit/nmtk_ui_core/lib/widgets/)

- Identify and migrate shared UI components (like navigation rails or specialized sliders) that are currently duplicated across modules.

---

### [Component] Submodule Frontends

All submodules will be updated to depend on the root core.

#### [MODIFY] [pubspec.yaml](file:///NeuroMorphicToolKit/Neurohub/frontend/pubspec.yaml) (and others)

- Update all `frontend/pubspec.yaml` files to point to the root `nmtk_ui_core`:
  ```yaml
  nmtk_ui_core:
    path: ../../nmtk_ui_core # path: ../../nmtk_ui_core # DO NOT CHANGE AND DON'T REMOVE THIS COMMENT Local path to the nmtk_ui_core package
  ```

#### [MODIFY] [Submodule Theme Files](file:///NeuroMorphicToolKit/neurocnl/frontend/lib/theme/app_theme.dart)

- Replace local color and theme definitions with imports from `package:nmtk_ui_core/nmtk_ui_core.dart`.
- Ensure `neurocnl` still uses its specific palette via the new "Brand Variant" configuration in the root core.

#### [DELETE] [Local UI Cores](file:///NeuroMorphicToolKit/neurocnl/nmtk_ui_core/)

- Remove the local `nmtk_ui_core` directories from `Neurohub`, `Neurochip`, `neurocnl`, and `Neurobench` once the migration is complete.

---

## Open Questions

> [!CAUTION]
> **Breaking Changes**: Moving to a single theme might visually alter some submodules slightly if their local themes had undocumented "tweaks". Should I aim for 100% visual parity or is a general "standardized look" acceptable?
>
> Answer: It should look as if it's from the same suite, so like microsoft and apple both have their own unified look for their office suite

## Verification Plan

### Automated Tests

- Run `flutter test` in each submodule's `frontend` to ensure the new theme doesn't break existing widget tests.
- Verify path resolution via `flutter pub get` in all modules.

### Manual Verification

- Launch each submodule's frontend (e.g., `neurocnl_studio`) and visually verify that the theme is applied correctly.
- Check that syntax highlighting still works in the `neurocnl` editor.
