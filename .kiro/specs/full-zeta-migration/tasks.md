# Implementation Plan: full-zeta-migration

## Overview

Pure code-level refactor eliminating all raw Material widget usage and inconsistent design-token references across five module packages and `nmtk_ui_core`. No new widgets, no new packages, no architecture changes. Tasks are ordered into three waves: the `nmtk_ui_core` foundation must land first (Wave 1), module sweeps run next (Wave 2, parallel where file sets are disjoint), and the `nmtk_ui_core` widget radius/gap sweep closes last (Wave 3).

The implementation language is **Dart / Flutter**.

---

## Tasks

- [x] 1. nmtk_ui_core foundation changes (Wave 1 — must land before all module tasks)
  - [x] 1.1 Fix `_seedForVariant`, `_neurocnlDarkTheme`, and `_neurocnlLightTheme` in `app_theme.dart`
    - In `_seedForVariant`: replace `NmtkNeurocnlTokens.primary` with `const Color(0xFF8B5CF6)` (Pattern 1a)
    - In `_neurocnlDarkTheme()`: change `ColorScheme.fromSeed(seedColor:)`, `ElevatedButtonThemeData.backgroundColor`, `OutlinedButtonThemeData.foregroundColor`, and `OutlinedButtonThemeData.side` to reference `Color(0xFF8B5CF6)` (Pattern 1b)
    - In `_neurocnlLightTheme()`: change `ColorScheme.fromSeed(seedColor:)` and `ElevatedButtonThemeData.backgroundColor` to reference `Color(0xFF7C3AED)` (Pattern 1c)
    - After each change run `dart analyze nmtk_ui_core/` and confirm zero errors
    - _Requirements: 1.2, 1.8_

  - [x] 1.2 Add restricted-use doc comments to `NmtkNeurocnlTokens` status fields in `app_theme.dart`
    - Add `/// Restricted to CNL-editor syntax diagnostics and network-graph canvas elements only. For module-level status UI, use [NmtkShellTokens] instead.` above `success`, `error`, and `warning` fields (Pattern 1d)
    - Verify `grep -c 'NmtkNeurocnlTokens\.primary' nmtk_ui_core/lib/app_theme.dart` returns 0 inside seed/button-theme calls
    - _Requirements: 1.7_

  - [x] 1.3 Add `instrumentChannelPalette` static const to `NmtkShellTokens` in `shell_tokens.dart`
    - Add the 8-entry `static const List<Color> instrumentChannelPalette` field with the canonical cyan/teal values `[0xFF06B6D4, 0xFF65C4C4, 0xFF91E1E1, 0xFFBCFBFB, 0xFF0F766E, 0xFF1A8080, 0xFF003535, 0xFF0A1616]` (Pattern 1e)
    - Run `dart analyze nmtk_ui_core/` and confirm zero errors
    - _Requirements: 6.1, 6.2_

  - [x] 1.4 Write unit tests for `instrumentChannelPalette` invariants
    - Create `nmtk_ui_core/test/migration_properties_test.dart`
    - **Palette length invariant:** `expect(NmtkShellTokens.instrumentChannelPalette.length, equals(8))`
    - **Palette membership invariant:** assert every entry is a member of the canonical 8-color set
    - **Font constant consistency:** `expect(NmtkFontFamilies.monospace, equals('JetBrains Mono'))` and `expect(NmtkFontFamilies.package, equals('nmtk_ui_core'))`
    - **Theme seed smoke:** assert `neurocnl` dark theme `colorScheme.primary.value` is not `0xFF38BDF8`
    - _Requirements: 6.1, 6.2, 5.1, 1.2_

  - [x] 1.5 Write property test for channel color modulo wrap (Property 3)
    - **Property 3: Channel color index modulo wrap — no RangeError, correct color**
    - **Validates: Requirements 6.3, 6.7**
    - Add to `nmtk_ui_core/test/migration_properties_test.dart`
    - For randomly generated `(N: 1..1000, i: 0..9999)` pairs (min 100 iterations): assert `NmtkShellTokens.instrumentChannelPalette[i % NmtkShellTokens.instrumentChannelPalette.length]` returns a valid `Color`, no `RangeError` is thrown, and the returned color is a member of the canonical 8-color set

- [x] 2. neurocnl `FilledButton` → `ZetaButton` sweep (Wave 2)
  - [x] 2.1 Migrate all `FilledButton` instances in neurocnl to `ZetaButton` (Pattern A)
    - Files: `lib/screens/studio_screen.dart` (8), `lib/widgets/cnl_sentence_builder_dialog.dart` (1), `lib/widgets/cnl_editor.dart` (1), `lib/widgets/simulator_panel.dart` (2), `lib/widgets/nir_importer_tab.dart` (2, check for `FilledButton.icon`), `lib/widgets/training_inspector_panel.dart` (1), `lib/widgets/template_load_guard.dart` (1)
    - Apply A1–A7: basic → `ZetaButton(onPressed:, label:)`; tonal → `type: ZetaButtonType.subtle`; icon → `leading:`; disabled → `onPressed: null`; loading-state `CircularProgressIndicator` children removed; style overrides mapped to `ZetaButtonType`; non-Text children annotated with `// ZETA-MIGRATION-TODO: non-Text child, manual migration required`
    - Add `import 'package:nmtk_ui_core/nmtk_ui_core.dart';` to any file missing it
    - Run `dart analyze neurocnl/frontend/` after each file; confirm zero `undefined_identifier` / `argument_type_not_assignable` errors
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7_

- [x] 3. neurocnl `TextField`/`TextFormField` + monospace sweep (Wave 2, after Task 2)
  - [x] 3.1 Migrate all `TextField` and `TextFormField` instances in neurocnl to `ZetaTextInput` (Pattern B)
    - Files: `studio_screen.dart` (4), `cnl_editor.dart` (2), `simulator_panel.dart` (2), `server_setup_screen.dart` (1), `project_screen.dart` (2), `sweep_screen.dart` (4), `learning_config_panel.dart` (1), `akida_deploy_panel.dart` (1)
    - Apply full parameter mapping table: `hintText` → `hint`, `labelText` → `label`, `helperText` appended to `hint`, `prefixIcon` → `leading`, `suffixIcon` → `trailing`, `enabled` → `disabled: !enabled`, `validator` preserved; unmapped params dropped with `// ZETA-MIGRATION-TODO: <param> dropped`
    - Run `dart analyze neurocnl/frontend/` after each file
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.7, 3.8_

  - [x] 3.2 Migrate bare monospace font-family strings in neurocnl (Pattern D)
    - Files: `lib/screens/export_screen.dart` (1), `lib/widgets/nir_importer_tab.dart` (1), `lib/screens/export_dialog.dart` (1), `lib/screens/simulation_dashboard.dart` (1)
    - Replace `fontFamily: 'monospace'` (and `'Courier'` / `'Consolas'` if found) with `fontFamily: NmtkFontFamilies.monospace, package: NmtkFontFamilies.package`
    - Add `import 'package:nmtk_ui_core/nmtk_ui_core.dart';` if not present
    - Run `dart analyze neurocnl/frontend/` after each file
    - _Requirements: 5.1, 5.2, 5.3_

  - [x] 3.3 Write property test for TextField → ZetaTextInput parameter mapping (Property 1)
    - **Property 1: TextField/ZetaTextInput parameter mapping completeness**
    - **Validates: Requirements 3.3, 3.4**
    - Add to `nmtk_ui_core/test/migration_properties_test.dart`
    - For randomly generated `TextFieldConfig` structs (random subsets of: `controller`, `onChanged`, `keyboardType`, `obscureText`, `maxLines`, `enabled`, `focusNode`, `hintText`, `labelText`, `helperText`, `prefixIcon`, `suffixIcon`, `errorText`, `validator`) with min 100 iterations: assert each `ZetaTextInput` field equals the corresponding mapped value, `hint` = concatenation of `hintText` + `helperText` when both present, `disabled` = `!enabled` when set, `leading` = `prefixIcon`, `trailing` = `suffixIcon`

  - [x] 3.4 Write property test for validator round-trip (Property 2)
    - **Property 2: Validator round-trip — validator return propagates to `errorText`**
    - **Validates: Requirements 3.6**
    - Add to `nmtk_ui_core/test/migration_properties_test.dart`
    - For randomly generated `(validator, inputString)` pairs (min 100 iterations): assert that when `validator(inputString)` returns a non-null string `e` the `ZetaTextInput.errorText` equals `e`; when `validator(inputString)` returns `null` then `errorText` is `null`

- [x] 4. neurocnl `Colors.X` + channel palette sweep (Wave 2, after Task 3)
  - [x] 4.1 Replace raw `Colors.X` status references in neurocnl (Pattern C)
    - Files: `lib/widgets/simulator_panel.dart`, `lib/widgets/training_inspector_panel.dart`
    - Replace `Colors.green` → `NmtkShellTokens.of(context).healthyColor`, `Colors.red`/`redAccent` → `errorColor`, `Colors.orange` → `warningColor` or `degradedColor` (annotate if ambiguous), `Colors.grey` → `metadataForeground` (text) or `subtleBorder` (chart grid), `Colors.black54` → `metadataForeground`
    - For `CustomPainter` contexts without `BuildContext`: add color as constructor parameter sourced from `NmtkShellTokens.of(context)` in the calling `build()` method (Pattern C2)
    - Replace `NmtkNeurocnlTokens.success` → `NmtkShellTokens.of(context).healthyColor` and `NmtkNeurocnlTokens.error` → `NmtkShellTokens.of(context).errorColor` in any status-indicator widget (`training_inspector_panel.dart`)
    - _Requirements: 1.3, 1.4, 1.5, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6_

  - [x] 4.2 Replace channel color list in `sensor_time_series_chart.dart` with `instrumentChannelPalette` (Pattern F)
    - Replace inline `List<Color>` / `Colors.X` channel assignments with `NmtkShellTokens.instrumentChannelPalette`
    - If a `CustomPainter` receives colors, update its constructor to accept `List<Color> channelColors` and pass `NmtkShellTokens.instrumentChannelPalette` from the calling `build()` method
    - Run `dart analyze neurocnl/frontend/` after all changes
    - Verify `grep -r "Colors\.(blue|cyan|teal)" neurocnl/frontend/lib/widgets/sensor_time_series_chart.dart` returns 0 lines
    - _Requirements: 6.3, 6.6, 6.7_

- [x] 5. Neurohub sweep (Wave 2, parallel with Tasks 3–4)
  - [x] 5.1 Migrate `TextField`/`TextFormField` instances in Neurohub to `ZetaTextInput` (Pattern B)
    - Files: `lib/screens/login_screen.dart` (6), `lib/screens/new_project_screen.dart` (2), `lib/screens/share_model_screen.dart` (3), `lib/screens/asset_library_screen.dart` (1), `lib/screens/dashboard_screen.dart` (1)
    - Apply full parameter mapping; add `nmtk_ui_core` import where missing
    - Run `dart analyze Neurohub/frontend/` after each file
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.7, 3.8_

  - [x] 5.2 Replace raw `Colors.X` references in Neurohub (Pattern C)
    - `lib/screens/login_screen.dart`: `Colors.red` → `NmtkShellTokens.of(context).errorColor`
    - `lib/widgets/onboarding_tour.dart`: `Colors.black54` → `NmtkShellTokens.of(context).metadataForeground`
    - `Colors.blue` in Neurohub files → `NmtkShellTokens.of(context).commandPalette.accent`
    - Run `dart analyze Neurohub/frontend/`
    - _Requirements: 4.2, 4.5, 4.6, 4.7_

- [x] 6. Neurobench sweep (Wave 2, parallel)
  - [x] 6.1 Migrate `FilledButton` instances in Neurobench to `ZetaButton` (Pattern A)
    - File: `lib/screens/workbench_shell.dart` (2)
    - Apply A1–A7 as appropriate; add `nmtk_ui_core` import if missing
    - Run `dart analyze Neurobench/frontend/` after changes
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7_

  - [x] 6.2 Migrate `TextField` instances in Neurobench to `ZetaTextInput` (Pattern B)
    - Files: `lib/screens/workbench_shell.dart` (3), `lib/screens/report_builder.dart` (1)
    - Apply full parameter mapping; add import if missing
    - Run `dart analyze Neurobench/frontend/` after each file
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.7, 3.8_

  - [x] 6.3 Replace raw `Colors.X` references in Neurobench chart and table widgets (Pattern C)
    - Files: `lib/widgets/metric_diff_table.dart`, `lib/widgets/robustness_curve_chart.dart`, `lib/widgets/target_comparison_grid.dart`, `lib/widgets/run_history_timeline.dart`, `lib/widgets/trend_chart.dart`
    - Apply Pattern C1 for widget `build()` contexts; apply Pattern C2 (constructor param) for `CustomPainter` subclasses in `robustness_curve_chart.dart` and `trend_chart.dart`
    - `Colors.green` → `healthyColor`, `Colors.red`/`redAccent` → `errorColor`, `Colors.orange` → `warningColor` / `degradedColor` (annotate if ambiguous), `Colors.grey` → `subtleBorder` (grid lines) or `metadataForeground` (text)
    - Run `dart analyze Neurobench/frontend/` after all changes
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.6_

- [x] 7. Neurosense sweep (Wave 2, parallel; requires Task 1 for `instrumentChannelPalette`)
  - [x] 7.1 Migrate `TextField` and monospace font-family string in Neurosense (Patterns B + D)
    - `lib/screens/recording_controls.dart`: migrate 2 `TextField` instances (Pattern B) + replace `fontFamily: 'monospace'` with `NmtkFontFamilies.monospace` + `package: NmtkFontFamilies.package` (Pattern D)
    - `lib/screens/replay_controls.dart`: migrate 1 `TextField` instance (Pattern B)
    - Add `import 'package:nmtk_ui_core/nmtk_ui_core.dart';` where missing
    - Run `dart analyze Neurosense/frontend/` after each file
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.7, 3.8, 5.1, 5.3_

  - [x] 7.2 Replace `Colors.X` status references in `support_level_badge.dart` (Pattern C)
    - Replace all `Colors.X` status color occurrences with corresponding `NmtkShellTokens.of(context)` fields using Pattern C1
    - Run `dart analyze Neurosense/frontend/`
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6_

  - [x] 7.3 Replace channel color lists in `live_signal_viewer.dart` and `spike_encoding_panel.dart` with `instrumentChannelPalette` (Pattern F)
    - For each file: replace the `List<Color>` channel field and all `Colors.X` channel color references with `NmtkShellTokens.instrumentChannelPalette`
    - For any `CustomPainter` in these widgets: add `List<Color> channelColors` constructor parameter; pass `NmtkShellTokens.instrumentChannelPalette` from the `build()` method
    - Run `dart analyze Neurosense/frontend/`
    - Verify `grep -r "Colors\.(blue|cyan|teal)" Neurosense/frontend/lib/widgets/live_signal_viewer.dart Neurosense/frontend/lib/widgets/spike_encoding_panel.dart` returns 0 lines
    - _Requirements: 6.3, 6.4, 6.5, 6.7_

- [x] 8. nmtk/neuro_toolkit sweep (Wave 2, parallel)
  - [x] 8.1 Migrate `FilledButton` instances in nmtk to `ZetaButton` (Pattern A)
    - File: `lib/screens/backend_setup.dart` (2, including one `FilledButton.tonal`)
    - Apply A1–A4 as appropriate; add `nmtk_ui_core` import if missing
    - Run `dart analyze nmtk/neuro_toolkit/` after changes
    - _Requirements: 2.1, 2.2, 2.4, 2.5_

  - [x] 8.2 Migrate `TextField` instances in nmtk to `ZetaTextInput` (Pattern B)
    - Files: `lib/screens/server_setup.dart` (1), `lib/screens/backend_setup.dart` (1), `lib/screens/settings.dart` (4)
    - Apply full parameter mapping; add import if missing
    - Run `dart analyze nmtk/neuro_toolkit/` after each file
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.7, 3.8_

  - [x] 8.3 Migrate monospace font-family string in `python_setup.dart` (Pattern D)
    - File: `lib/screens/python_setup.dart` (1 instance)
    - Replace `fontFamily: 'monospace'` with `fontFamily: NmtkFontFamilies.monospace, package: NmtkFontFamilies.package`
    - Add `import 'package:nmtk_ui_core/nmtk_ui_core.dart';` if missing
    - Run `dart analyze nmtk/neuro_toolkit/`
    - _Requirements: 5.1, 5.2, 5.3_

- [x] 9. Wave 2 checkpoint — verify all module sweeps pass analysis and grep gates
  - Ensure all tests pass, ask the user if questions arise.
  - Run all six canonical CI grep commands against the completed module packages and confirm zero matches in each
  - Run `dart analyze` on each of the five module package roots and confirm zero errors

- [x] 10. nmtk_ui_core widgets radius/gap sweep (Wave 3)
  - [x] 10.1 Replace `BorderRadius.circular(N)` numeric literals in `nmtk_ui_core/lib/widgets/` with token calls (Pattern E)
    - `desktop_scaffold.dart`: `BorderRadius.circular(6)` → `BorderRadius.circular(tokens.radiusSm)` (remove `const` if needed)
    - `surface_card.dart`: `BorderRadius.circular(12)` → `BorderRadius.circular(tokens.radiusSm)`
    - `summary_card.dart`: `BorderRadius.circular(12)` → `BorderRadius.circular(tokens.radiusSm)`
    - `pipeline_stepper.dart`: `BorderRadius.circular(12)` → `BorderRadius.circular(tokens.radiusSm)`
    - `validation_chip.dart`: `BorderRadius.circular(999)` → `BorderRadius.circular(tokens.radiusChip)`
    - `workflow_step_row.dart`: `BorderRadius.circular(999)` → `BorderRadius.circular(tokens.radiusChip)`
    - `info_chip.dart`: `BorderRadius.circular(999)` → `BorderRadius.circular(tokens.radiusChip)`
    - For each file: obtain `tokens` via `NmtkShellTokens.of(context)`; remove `const` from any enclosing widget expression that contains a token lookup
    - Retain any intentional platform override with `// ZETA-MIGRATION-EXEMPT: <reason>`
    - _Requirements: 7.1, 7.2, 7.3, 7.5, 7.7_

  - [x] 10.2 Replace `EdgeInsets.fromLTRB` with token-based padding in `workspace_shell.dart` (Pattern E)
    - Replace `EdgeInsets.fromLTRB(20, 20, 10, 20)` with `EdgeInsets.all(tokens.sectionGap)`
    - If the asymmetric right padding was intentional, use `EdgeInsets.symmetric(horizontal: tokens.sectionGap, vertical: tokens.sectionGap)` and annotate with `// ZETA-MIGRATION-TODO: asymmetric padding replaced with symmetric; verify visually`
    - Run `dart analyze nmtk_ui_core/`
    - Verify `grep -r 'EdgeInsets\.fromLTRB' nmtk_ui_core/lib/widgets/workspace_shell.dart` returns 0 lines
    - _Requirements: 7.4_

- [x] 11. Final CI verification — run all six canonical grep commands
  - Ensure all tests pass, ask the user if questions arise.
  - Execute the six canonical grep commands covering all five module packages plus `nmtk_ui_core/lib/widgets/`:
    1. `grep -r 'FilledButton\b' neurocnl Neurohub Neurobench Neurosense nmtk --include='*.dart' | grep -v 'ZETA-MIGRATION-TODO'` → 0 matches
    2. `grep -r '\bTextField\(' neurocnl Neurohub Neurobench Neurosense nmtk --include='*.dart'` → 0 matches
    3. `grep -r '\bTextFormField\(' neurocnl Neurohub Neurobench Neurosense nmtk --include='*.dart'` → 0 matches
    4. `grep -r "Colors\.\(green\|red\|redAccent\|orange\|grey\|black54\)" Neurobench Neurosense Neurohub neurocnl --include='*.dart' | grep -v 'ZETA-MIGRATION-TODO'` → 0 matches
    5. `grep -r "fontFamily:.*'monospace'" neurocnl Neurosense nmtk --include='*.dart'` → 0 matches
    6. `grep -r 'BorderRadius\.circular([0-9]' nmtk_ui_core/lib/widgets --include='*.dart' | grep -v 'ZETA-MIGRATION-EXEMPT'` → 0 matches
  - Run `dart analyze` on all six package roots: `nmtk_ui_core/`, `neurocnl/frontend/`, `Neurohub/frontend/`, `Neurobench/frontend/`, `Neurosense/frontend/`, `nmtk/neuro_toolkit/`
  - Confirm zero errors across all packages before declaring migration complete

---

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP pass
- Wave 1 (Task 1) must complete before any module sweep begins — consumers cannot compile without `instrumentChannelPalette` and will produce incorrect theme seeds without the seed-color fix
- Within Wave 2, Tasks 5–8 are fully independent of Tasks 2–4 and of each other; Tasks 2 → 3 → 4 must run sequentially because they touch overlapping neurocnl files
- Wave 3 (Task 10) touches only `nmtk_ui_core/lib/widgets/` and has no module file overlap; it can technically run in parallel with Wave 2 but is placed last for clarity
- `ZETA-MIGRATION-TODO` annotations are post-migration backlog items; they do not block merging but must be resolved before the feature is fully closed
- `ZETA-MIGRATION-EXEMPT` annotations exempt a line from the CI grep absence check; always include a one-sentence justification
- All property tests must run a minimum of 100 iterations
- Each task's verification step (`dart analyze` + grep check) is a blocker; do not advance to the next task until it passes

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "1.3"] },
    { "id": 1, "tasks": ["1.4", "1.5", "2.1"] },
    { "id": 2, "tasks": ["3.1", "3.2", "5.1", "5.2", "6.1", "6.2", "7.1", "8.1", "8.2", "8.3"] },
    { "id": 3, "tasks": ["3.3", "3.4", "4.1", "6.3", "7.2", "7.3"] },
    { "id": 4, "tasks": ["4.2"] },
    { "id": 5, "tasks": ["10.1", "10.2"] }
  ]
}
```
