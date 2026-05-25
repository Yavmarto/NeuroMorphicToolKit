# Requirements Document

## Introduction

The NeuroMorphicToolKit (NMTK) Flutter desktop suite has a partially integrated Zeta (`zeta_flutter ^1.4.5`) design system. The theme infrastructure (`NmtkZetaTheme.wrap`, `NmtkShellTokens`, `AppTheme`) is correctly wired, but widget usage and design-token adoption are inconsistent across five active modules: **neurocnl**, **Neurohub**, **Neurobench**, **Neurosense**, and **nmtk/neuro_toolkit**.

This migration resolves seven categories of audit findings:

1. Semantic color conflict — neurocnl Studio interactive primary vs. `state-running`
2. Material `FilledButton` → `ZetaButton` (~23 instances)
3. Material `TextField`/`TextFormField` → `ZetaTextInput` (~35 instances)
4. Raw `Colors.X` status values → `NmtkShellTokens` semantic tokens
5. Bare `'monospace'` font-family string → `NmtkFontFamilies.monospace` + `package:`
6. Ad-hoc multi-channel signal color lists → `NmtkInstrumentChannelPalette`
7. Hardcoded `BorderRadius`/`EdgeInsets` literals → `NmtkShellTokens` radius and gap tokens

After this migration, every module's UI layer references only the token vocabulary defined in `nmtk_ui_core` and sourced from `docs/DESIGN.md` / `.impeccable/design.json`. No module-level widget may reference a raw `Color(0xFFXXXXXX)` literal, a Material-only input or button widget, or a bare font-family string for purposes covered by the token system.

---

## Glossary

- **Studio_Migrator**: The migration tooling and code-change process responsible for resolving Issues 1–7.
- **NmtkShellTokens**: The `ThemeExtension<NmtkShellTokens>` defined in `nmtk_ui_core/lib/shell_tokens.dart` that exposes semantic colors (`healthyColor`, `errorColor`, `runningColor`, `degradedColor`, `warningColor`, `liveColor`), surface colors (`chromeBorder`, `subtleBorder`, `metadataForeground`), radius tokens (`radiusSm`, `radiusMd`, `radiusLg`, `radiusChip`), and gap tokens (`sectionGap`, `compactGap`).
- **NmtkNeurocnlTokens**: The static color constants in `nmtk_ui_core/lib/app_theme.dart` scoped to the neurocnl module. Contains CNL editor syntax colors and network-graph node/edge colors. Must not be used for module-level status UI after this migration.
- **NmtkFontFamilies**: The class in `nmtk_ui_core/lib/app_theme.dart` exposing `NmtkFontFamilies.monospace` (`'JetBrains Mono'`) and `NmtkFontFamilies.package` (`'nmtk_ui_core'`).
- **NmtkInstrumentChannelPalette**: A new constant defined in `NmtkShellTokens` providing exactly 8 instrument-mode colors (cyan/teal family) for multi-channel signal visualizations.
- **ZetaButton**: The `ZetaButton` widget from `zeta_flutter`, exported via `nmtk_ui_core/lib/zeta_theme.dart`. Replaces all Material `FilledButton`, `FilledButton.tonal`, and `FilledButton.icon` usages.
- **ZetaTextInput**: The `ZetaTextInput` widget from `zeta_flutter`, exported via `nmtk_ui_core/lib/zeta_theme.dart`. Replaces all Material `TextField` and `TextFormField` usages in module UI screens.
- **Studio_Palette**: The `NmtkShellTokens.studioPalette` field of type `NmtkShellModePalette`, whose `accent` property holds `Color(0xFF8B5CF6)` (dark) / `Color(0xFF7C3AED)` (light) — the Studio Violet interactive primary.
- **Status_Color_Set**: The six semantic colors defined in `NmtkShellTokens`: `healthyColor` (`#22C55E`), `runningColor` (`#38BDF8`), `degradedColor` (`#F59E0B`), `warningColor` (`#F97316`), `errorColor` (`#EF4444`), `liveColor` (`#E11D48`).
- **Instrument_Palette**: The `NmtkShellModePalette` stored in `NmtkShellTokens.instrumentPalette`, whose `accent` is `#06B6D4` (dark) / `#0F766E` (light).
- **Affected_Modules**: The five Flutter module packages in scope: `neurocnl`, `Neurohub`, `Neurobench`, `Neurosense`, `nmtk/neuro_toolkit`.

---

## Requirements

---

### Requirement 1: Semantic Color Conflict Resolution (P0)

**User Story:** As a designer reviewing the NMTK suite, I want the neurocnl Studio module's interactive primary color to be Studio Violet and all status indicators to use the shared semantic palette, so that `#38BDF8` exclusively communicates the "running" state across every module and the design system remains semantically pure.

#### Acceptance Criteria

1. IF a neurocnl UI widget file references `NmtkNeurocnlTokens.primary` as an interactive accent color (i.e., applied to a button, link, focused border, or selected indicator that is not a CNL-graph node, graph edge, or syntax-highlight element), THEN THE `Studio_Migrator` SHALL replace that reference with `NmtkShellTokens.of(context).studioPalette.accent`.

2. WHEN the neurocnl module theme is constructed in `AppTheme._neurocnlDarkTheme()` and `AppTheme._neurocnlLightTheme()`, THE seed color passed to `ColorScheme.fromSeed` SHALL be `Color(0xFF8B5CF6)` (dark) / `Color(0xFF7C3AED)` (light), sourced from `NmtkShellTokens.dark.studioPalette.accent` and `NmtkShellTokens.light.studioPalette.accent` respectively, rather than `NmtkNeurocnlTokens.primary` (`Color(0xFF38BDF8)`).

3. IF a neurocnl widget file references `NmtkNeurocnlTokens.success` in a status-indicator context (i.e., in a widget whose name or semantic role communicates health, completion, or success to the user — not in a CNL syntax-diagnostic or graph-canvas context), THEN THE `Studio_Migrator` SHALL replace that reference with `NmtkShellTokens.of(context).healthyColor`.

4. IF a neurocnl widget file references `NmtkNeurocnlTokens.error` in a status-indicator context (as defined in AC3), THEN THE `Studio_Migrator` SHALL replace that reference with `NmtkShellTokens.of(context).errorColor`.

5. WHILE a neurocnl status-indicator widget (any widget whose class name or build-method comment identifies it as communicating module health, pipeline state, or run status) is rendered, THE widget SHALL source its color exclusively from the `Status_Color_Set` defined in `NmtkShellTokens`, not from `NmtkNeurocnlTokens`.

6. IF a neurocnl Dart file contains a `Color` literal or constant reference whose resolved value equals `0xFF38BDF8` and that file's widget tree contains the literal outside a CNL-graph node, graph edge, or syntax-highlight assignment, THEN THE `Studio_Migrator` SHALL emit a build-time error of the form `[NMTK-MIGRATION-VIOLATION] <file>:<line>: Color(0xFF38BDF8) used as accent; replace with NmtkShellTokens.studioPalette.accent` before compilation completes, halting the build.

7. THE `NmtkNeurocnlTokens` class SHALL retain its `success`, `error`, and `warning` fields. Each field SHALL carry a doc comment of the form: `/// Restricted to CNL-editor syntax diagnostics and network-graph canvas elements only. For module-level status UI, use NmtkShellTokens instead.`

8. WHEN `AppTheme._neurocnlDarkTheme()` sets `elevatedButtonTheme` or `outlinedButtonTheme`, THE background and foreground colors in those theme objects SHALL reference `Color(0xFF8B5CF6)` (Studio Violet), not `NmtkNeurocnlTokens.primary`.

#### Correctness Property

**Invariant — no status widget in neurocnl uses the running color as a primary accent:**
For every `Color` value applied to a non-graph, non-syntax-highlight widget in the neurocnl module, that value SHALL NOT equal `Color(0xFF38BDF8)` unless the widget's semantic role is `state-running`. This is verifiable as a widget-test assertion iterating over all `ColoredBox`, `Container(color:)`, `ButtonStyle.backgroundColor`, and `TextStyle.color` values in the neurocnl widget tree.

**Absence invariant — `NmtkNeurocnlTokens.primary` does not appear in theme seed calls:**
A grep search for `NmtkNeurocnlTokens\.primary` in `nmtk_ui_core/lib/app_theme.dart` inside `ColorScheme.fromSeed` calls SHALL return zero matches after migration.

---

### Requirement 2: FilledButton → ZetaButton Migration

**User Story:** As a developer maintaining the NMTK suite, I want all Material `FilledButton` usages replaced with `ZetaButton`, so that button appearance, interaction states, and accessibility properties are governed by the Zeta design system rather than Material defaults.

#### Acceptance Criteria

1. IF a file in `Affected_Modules` contains a `FilledButton(onPressed:, child: Text(...))` call, THEN THE `Studio_Migrator` SHALL replace it with `ZetaButton(onPressed:, label: <string>)`, extracting the label string from the `Text` child. IF the `child` is not a `Text` widget, THE `Studio_Migrator` SHALL leave a `// ZETA-MIGRATION-TODO: non-Text child, manual migration required` comment at the call site.

2. IF a file in `Affected_Modules` contains a `FilledButton.tonal(onPressed:, child:)` call, THEN THE `Studio_Migrator` SHALL replace it with `ZetaButton(onPressed:, label:, type: ZetaButtonType.subtle)`.

3. IF a file in `Affected_Modules` contains a `FilledButton.icon(onPressed:, icon:, label:)` call, THEN THE `Studio_Migrator` SHALL replace it with `ZetaButton(onPressed:, label: <label-string>, leading: <icon-widget>)`.

4. WHEN a file is migrated under this requirement, THE file SHALL have an import for `package:nmtk_ui_core/nmtk_ui_core.dart` or `package:zeta_flutter/zeta_flutter.dart` that brings `ZetaButton` into scope. IF the file did not previously import either package, THE `Studio_Migrator` SHALL add `import 'package:nmtk_ui_core/nmtk_ui_core.dart';` to the import block.

5. THE `Studio_Migrator` SHALL migrate all 23 confirmed instances across the following files: `studio_screen.dart` (8), `workbench_shell.dart` (2), `cnl_sentence_builder_dialog.dart` (1), `cnl_editor.dart` (1), `simulator_panel.dart` (2), `nir_importer_tab.dart` (2), `training_inspector_panel.dart` (1), `template_load_guard.dart` (1), `backend_setup.dart` (2, including `FilledButton.tonal`).

6. IF a `FilledButton` usage carries a `style: FilledButton.styleFrom(backgroundColor: <Color>)` or `style: ButtonStyle(backgroundColor: MaterialStateProperty.all(<Color>))` override, THEN THE `Studio_Migrator` SHALL translate the override to the nearest `ZetaButtonType` according to this mapping: `NmtkNeurocnlTokens.primary` or `studioPalette.accent` → `ZetaButtonType.primary`; `NmtkShellTokens.errorColor` → `ZetaButtonType.negative`; `Colors.grey` or neutral → `ZetaButtonType.subtle`. Raw color literals not matching a known token SHALL be replaced with `ZetaButtonType.primary` and annotated with `// ZETA-MIGRATION-TODO: verify button type`.

7. IF a `FilledButton` or `FilledButton.icon` call has `onPressed: null` (disabled state), THEN THE migrated `ZetaButton` SHALL also have `onPressed: null`, relying on `ZetaButton`'s built-in disabled rendering rather than a custom disabled style.

#### Correctness Property

**Absence invariant — zero `FilledButton` references in migrated files:**
A grep search for the pattern `\bFilledButton\b` across all Dart files in `Affected_Modules` SHALL return zero matches after migration, excluding lines that contain `// ZETA-MIGRATION-TODO:`. This is verifiable as a CI lint rule or a property-based absence test iterating over the file set.

---

### Requirement 3: TextField/TextFormField → ZetaTextInput Migration

**User Story:** As a developer maintaining the NMTK suite, I want all Material `TextField` and `TextFormField` usages replaced with `ZetaTextInput`, so that all text inputs render with consistent Zeta-governed styling, focus behavior, and error state presentation.

#### Acceptance Criteria

1. IF a file in `Affected_Modules` contains a `TextField(...)` widget instantiation in a build method, THEN THE `Studio_Migrator` SHALL replace it with `ZetaTextInput(...)`.

2. IF a file in `Affected_Modules` contains a `TextFormField(...)` widget instantiation in a build method, THEN THE `Studio_Migrator` SHALL replace it with `ZetaTextInput(...)`, preserving any form validation logic via `ZetaTextInput`'s `validator` parameter.

3. WHEN migrating a `TextField` or `TextFormField`, THE `Studio_Migrator` SHALL map the following `InputDecoration` parameters to their `ZetaTextInput` equivalents: `hintText` → `hint`; `labelText` → `label`; `helperText` → `hint` (appended to hint if both are present); `prefixIcon` → `leading`; `suffixIcon` → `trailing`; `errorText` → `errorText`. Parameters with no `ZetaTextInput` equivalent SHALL be dropped and annotated with `// ZETA-MIGRATION-TODO: <param> has no ZetaTextInput equivalent`.

4. WHEN migrating a `TextField` or `TextFormField`, THE `Studio_Migrator` SHALL map the following behavioral parameters: `controller` → `controller`; `onChanged` → `onChanged`; `keyboardType` → `keyboardType`; `obscureText: true` → `obscureText: true`; `maxLines` → `maxLines`; `enabled` → `disabled: !enabled`; `focusNode` → `focusNode`. Any parameter not listed here and not handled by AC3 SHALL be dropped with a `// ZETA-MIGRATION-TODO: <param> dropped` comment.

5. THE `Studio_Migrator` SHALL migrate all `TextField` and `TextFormField` instances discovered across `Affected_Modules`, including but not limited to the 35 confirmed instances in: `studio_screen.dart` (4), `cnl_editor.dart` (2), `simulator_panel.dart` (2), `server_setup_screen.dart` (1), `project_screen.dart` (2), `sweep_screen.dart` (4), `learning_config_panel.dart` (1), `akida_deploy_panel.dart` (1), `workbench_shell.dart` (3), `report_builder.dart` (1), `recording_controls.dart` (2), `replay_controls.dart` (1), `dashboard_screen.dart` (1), `asset_library_screen.dart` (1), `share_model_screen.dart` (3), `new_project_screen.dart` (2), `login_screen.dart` (6), `server_setup.dart` (1), `backend_setup.dart` (1), `settings.dart` (4). WHEN additional instances are discovered beyond these 35, THE `Studio_Migrator` SHALL migrate those additional instances as well.

6. IF a `TextFormField` uses a `validator:` that returns a non-null `String` error message, THEN THE migrated `ZetaTextInput` SHALL surface that error message via its `errorText` parameter. IF the validator returns `null` (valid), `errorText` SHALL be `null`.

7. WHEN a file is migrated under this requirement, THE file SHALL have an import for `package:nmtk_ui_core/nmtk_ui_core.dart` or `package:zeta_flutter/zeta_flutter.dart` that brings `ZetaTextInput` into scope. IF the file did not previously import either package, THE `Studio_Migrator` SHALL add `import 'package:nmtk_ui_core/nmtk_ui_core.dart';` to the import block.

8. AFTER migration of each file, THE `Studio_Migrator` SHALL run `dart analyze <file_path>` and SHALL treat any `undefined_identifier` or `argument_type_not_assignable` error in the migrated file as a migration failure requiring a fix before proceeding to the next file.

#### Correctness Property

**Absence invariant — zero bare `TextField` or `TextFormField` widget instantiations in migrated files:**
A grep search for the patterns `\bTextField\(` and `\bTextFormField\(` across all Dart files in `Affected_Modules` SHALL return zero matches after migration. References to `TextEditingController` and variable declarations containing `TextField` in identifiers are exempt.

---

### Requirement 4: Raw Color Literal Replacement with Semantic Shell Tokens

**User Story:** As a designer reviewing NMTK screens, I want all raw `Colors.X` usages in status and metadata UI to reference `NmtkShellTokens` semantic tokens, so that the semantic purity rule (each status color has exactly one meaning) is enforced uniformly across the suite.

#### Acceptance Criteria

1. IF a file in the named set (`metric_diff_table.dart`, `robustness_curve_chart.dart`, `target_comparison_grid.dart`, `run_history_timeline.dart`, `trend_chart.dart`, `support_level_badge.dart`, `simulator_panel.dart`, `training_inspector_panel.dart`, `login_screen.dart`, `onboarding_tour.dart`) contains `Colors.green` or `Colors.green.shadeXXX`, THEN THE `Studio_Migrator` SHALL replace each occurrence with `NmtkShellTokens.of(context).healthyColor`. IF the occurrence is inside a `CustomPainter` or static context without a `BuildContext`, THE replacement SHALL use `NmtkShellTokens.healthyColor` as a static constant and the painter SHALL receive it as a constructor parameter.

2. IF a file in the named set contains `Colors.red` or `Colors.red.shadeXXX` or `Colors.redAccent`, THEN THE `Studio_Migrator` SHALL replace each occurrence with `NmtkShellTokens.of(context).errorColor` (or as a constructor parameter for painters).

3. IF a file in the named set contains `Colors.orange` or `Colors.orange.shadeXXX`, THEN THE `Studio_Migrator` SHALL replace each occurrence as follows: IF the surrounding widget communicates a threshold, approach, or non-fatal issue (per `DESIGN.md §2.3 Warning: Threshold approaching, non-fatal`), use `NmtkShellTokens.of(context).warningColor`; IF it communicates reduced capability where workflow can continue (per `DESIGN.md §2.3 Degraded: Reduced capability, workflow can continue`), use `NmtkShellTokens.of(context).degradedColor`. IF the intent cannot be determined from context, use `degradedColor` and annotate with `// ZETA-MIGRATION-TODO: verify degraded vs warning`.

4. IF a file in the named set contains `Colors.grey` or `Colors.grey.shadeXXX`, THEN THE `Studio_Migrator` SHALL replace each occurrence with `NmtkShellTokens.of(context).metadataForeground` (or as a constructor parameter for painters). IF a `Colors.grey` occurrence is a chart grid-line or axis tick color rather than text, use `NmtkShellTokens.of(context).subtleBorder` instead.

5. IF a file in the named set contains `Colors.black54`, THEN THE `Studio_Migrator` SHALL replace each occurrence with `NmtkShellTokens.of(context).metadataForeground`.

6. THE `Studio_Migrator` SHALL apply the replacements defined in AC1–AC5 to all occurrences within the following ten files: `metric_diff_table.dart`, `robustness_curve_chart.dart`, `target_comparison_grid.dart`, `run_history_timeline.dart`, `trend_chart.dart`, `support_level_badge.dart`, `simulator_panel.dart`, `training_inspector_panel.dart`, `login_screen.dart`, `onboarding_tour.dart`. THE migration of a named file that contains zero matching `Colors.X` references SHALL be considered complete with no changes required and no error emitted.

7. IF a file in the named set contains `Colors.blue` used as an interactive accent (button background, selected indicator, focused border) rather than as a status signal, THEN THE `Studio_Migrator` SHALL replace it with the mode-palette accent resolved from the file's module path: files under `neurocnl/` → `NmtkShellTokens.of(context).studioPalette.accent`; files under `Neurosense/`, `Neurochip/`, or `Neurobench/` → `NmtkShellTokens.of(context).instrumentPalette.accent`; files under `Neurohub/` or `nmtk/` → `NmtkShellTokens.of(context).commandPalette.accent`.

8. IF a `Colors.X` reference in the named set does not match any pattern defined in AC1–AC7 (e.g., `Colors.amber`, `Colors.purple`, or an opaque background tint), THEN THE `Studio_Migrator` SHALL leave the reference unchanged and annotate the line with `// ZETA-MIGRATION-TODO: unrecognized Colors.X usage — review manually`.

#### Correctness Property

**Absence invariant — zero `Colors.green`, `Colors.red`, `Colors.redAccent`, `Colors.orange`, `Colors.grey`, `Colors.black54` references in the ten named files:**
A grep search for `Colors\.(green|red|redAccent|orange|grey|black54)` in the ten named files SHALL return zero matches after migration, excluding lines annotated with `// ZETA-MIGRATION-TODO:`. Verified by CI grep assertion over the named file set.

---

### Requirement 5: Bare Monospace Font-Family String Replacement

**User Story:** As a developer maintaining the NMTK suite, I want all bare `fontFamily: 'monospace'` string references replaced with `NmtkFontFamilies.monospace` and `package: NmtkFontFamilies.package`, so that JetBrains Mono is consistently loaded from the `nmtk_ui_core` asset bundle rather than relying on a platform fallback.

#### Acceptance Criteria

1. IF a Dart file in the six named files (`export_screen.dart`, `nir_importer_tab.dart`, `export_dialog.dart`, `simulation_dashboard.dart`, `recording_controls.dart`, `python_setup.dart`) contains `fontFamily: 'monospace'` inside a `TextStyle(...)` constructor call, THEN THE `Studio_Migrator` SHALL replace it with `fontFamily: NmtkFontFamilies.monospace, package: NmtkFontFamilies.package`.

2. IF a Dart file in the six named files contains `fontFamily: 'Courier'` or `fontFamily: 'Consolas'` inside a `TextStyle(...)` constructor call, THEN THE `Studio_Migrator` SHALL replace it with `fontFamily: NmtkFontFamilies.monospace, package: NmtkFontFamilies.package`.

3. WHEN a file is migrated under AC1 or AC2, THE file SHALL have an import for `package:nmtk_ui_core/nmtk_ui_core.dart` that brings `NmtkFontFamilies` into scope. IF the file already imports `nmtk_ui_core`, no duplicate import SHALL be added.

4. IF a file requires the `nmtk_ui_core` import to be added but the import cannot be automatically inserted (e.g., a conflict with existing import aliases), THEN THE `Studio_Migrator` SHALL proceed with the font-family string replacement and emit a warning of the form `[NMTK-MIGRATION-WARNING] <file>: nmtk_ui_core import could not be added automatically — add manually`.

#### Correctness Property

**Absence invariant — zero bare monospace font-family string literals inside `TextStyle` constructors in the six named files:**
A grep search for `fontFamily:\s*'monospace'` in `export_screen.dart`, `nir_importer_tab.dart`, `export_dialog.dart`, `simulation_dashboard.dart`, `recording_controls.dart`, and `python_setup.dart` SHALL return zero matches after migration. A grep search for `fontFamily:\s*'Courier'` and `fontFamily:\s*'Consolas'` in the same files SHALL also return zero matches. Verified as a CI grep assertion.

**Round-trip property — font constant consistency:**
`NmtkFontFamilies.monospace` SHALL equal the compile-time constant `'JetBrains Mono'` and `NmtkFontFamilies.package` SHALL equal `'nmtk_ui_core'`. Any `TextStyle` using `fontFamily: NmtkFontFamilies.monospace, package: NmtkFontFamilies.package` SHALL resolve to the same font asset as a `TextStyle` using `fontFamily: 'JetBrains Mono', package: 'nmtk_ui_core'`. This is verifiable as a compile-time constant equality assertion in the unit test suite.

---

### Requirement 6: NmtkInstrumentChannelPalette Definition and Adoption

**User Story:** As a developer building signal-visualization widgets, I want a canonical fixed palette for multi-channel instrument signals defined in `NmtkShellTokens`, so that all channel color assignments are consistent, derive from the instrument-mode palette, and never use raw `Colors.X` literals.

#### Acceptance Criteria

1. THE `NmtkShellTokens` class SHALL expose a `static const List<Color> instrumentChannelPalette` containing exactly 8 entries.

2. THE 8 colors in `NmtkShellTokens.instrumentChannelPalette` SHALL be drawn exclusively from the instrument-mode teal/cyan family defined in `.impeccable/design.json`. The required values in list order are: `Color(0xFF06B6D4)`, `Color(0xFF65C4C4)`, `Color(0xFF91E1E1)`, `Color(0xFFBCFBFB)`, `Color(0xFF0F766E)`, `Color(0xFF1A8080)`, `Color(0xFF003535)`, `Color(0xFF0A1616)`.

3. WHEN a signal-visualization widget renders N signal channels (where 1 ≤ N ≤ 8), THE widget SHALL assign channel colors by indexing `NmtkShellTokens.instrumentChannelPalette` at `channelIndex % 8`.

4. IF `spike_encoding_panel.dart` contains a `List<Color>` or `Color[]` field used to assign colors to signal channels, THEN THE `Studio_Migrator` SHALL replace all raw color references in that field (and any corresponding painter constructor argument) with references to `NmtkShellTokens.instrumentChannelPalette`. IF the panel uses a `CustomPainter` that receives colors as constructor parameters, THE painter's parameter list SHALL be updated to accept `List<Color> channelColors` sourced from `NmtkShellTokens.instrumentChannelPalette`.

5. IF `live_signal_viewer.dart` (Neurosense) contains a `List<Color>` used to assign colors to signal channels, THEN THE `Studio_Migrator` SHALL replace all raw color references in that field (including both the widget layer and any painter constructor) with `NmtkShellTokens.instrumentChannelPalette`.

6. IF `sensor_time_series_chart.dart` (neurocnl) contains a `List<Color>` or `Colors.X` references used to assign colors to signal channels, THEN THE `Studio_Migrator` SHALL replace all raw color references in that field (including both the widget layer and any painter constructor) with `NmtkShellTokens.instrumentChannelPalette`.

7. WHEN a signal-visualization widget receives more than 8 channel inputs, THE widget SHALL wrap the channel index modulo 8, re-using palette entries. This overflow behavior SHALL NOT produce a `RangeError` at runtime and SHALL NOT prevent compilation.

#### Correctness Property

**Length invariant — palette always contains exactly 8 entries:**
`NmtkShellTokens.instrumentChannelPalette.length` SHALL equal `8`. This is a compile-time list-length assertion in the unit test suite: `expect(NmtkShellTokens.instrumentChannelPalette.length, equals(8))`.

**Set invariant — all palette entries are from the instrument palette:**
For every `Color c` in `NmtkShellTokens.instrumentChannelPalette`, `c` SHALL be a member of `{Color(0xFF06B6D4), Color(0xFF65C4C4), Color(0xFF91E1E1), Color(0xFFBCFBFB), Color(0xFF0F766E), Color(0xFF1A8080), Color(0xFF003535), Color(0xFF0A1616)}`. Verifiable as a property test iterating over every palette entry.

**Absence invariant — no raw `Colors.X` channel color references in the three named files:**
A grep search for `Colors\.(blue|green|orange|purple|red|teal|indigo|pink|amber)` in `spike_encoding_panel.dart`, `live_signal_viewer.dart`, and `sensor_time_series_chart.dart` SHALL return zero matches after migration.

---

### Requirement 7: Hardcoded Radius and Gap Literal Replacement

**User Story:** As a designer reviewing NMTK widget geometry, I want all hardcoded `BorderRadius.circular(N)` and non-standard `EdgeInsets` literals in module widgets replaced with `NmtkShellTokens` radius and gap tokens, so that corner radii and spacing are consistent, follow the DESIGN.md radius scale, and can be updated globally by changing a single token value.

#### Acceptance Criteria

1. IF `nmtk_ui_core/lib/widgets/desktop_scaffold.dart` contains `BorderRadius.circular(6)`, THEN THE `Studio_Migrator` SHALL replace it with `BorderRadius.circular(tokens.radiusSm)`, where `tokens` is obtained via `NmtkShellTokens.of(context)`. IF the call site is inside a `const` context, THE `Studio_Migrator` SHALL remove the `const` keyword from the enclosing expression to allow the runtime token lookup.

2. IF `surface_card.dart`, `summary_card.dart`, or `pipeline_stepper.dart` contains `BorderRadius.circular(12)`, THEN THE `Studio_Migrator` SHALL replace it with `BorderRadius.circular(tokens.radiusSm)` using `NmtkShellTokens.of(context)`.

3. IF `validation_chip.dart`, `workflow_step_row.dart`, or `info_chip.dart` contains `BorderRadius.circular(999)`, THEN THE `Studio_Migrator` SHALL replace it with `BorderRadius.circular(tokens.radiusChip)` using `NmtkShellTokens.of(context)`.

4. IF `workspace_shell.dart` contains `EdgeInsets.fromLTRB(20, 20, 10, 20)`, THEN THE `Studio_Migrator` SHALL replace it with `EdgeInsets.all(tokens.sectionGap)`. IF the asymmetric padding was intentional (verified by code comment), THE replacement SHALL be `EdgeInsets.symmetric(horizontal: tokens.sectionGap, vertical: tokens.sectionGap)` and annotated with `// ZETA-MIGRATION-TODO: asymmetric padding replaced with symmetric; verify visually`.

5. IF any widget file in `nmtk_ui_core/lib/widgets/` or an `Affected_Modules` screen contains `BorderRadius.circular(N)` where `N` is a numeric literal with `N < 12` and is not inside a file or line already covered by AC1, THEN THE `Studio_Migrator` SHALL replace it with `BorderRadius.circular(tokens.radiusSm)` using `NmtkShellTokens.of(context)`.

6. IF a widget class whose name ends in `Dialog` or `Sheet` in `nmtk_ui_core/lib/widgets/` or `Affected_Modules` contains a `BorderRadius.circular(N)` where `N` is a numeric literal, THEN THE `Studio_Migrator` SHALL replace it with `BorderRadius.circular(tokens.radiusMd)` (16dp) if `N ≤ 20` or `BorderRadius.circular(tokens.radiusLg)` (22dp) if `N > 20`, using `NmtkShellTokens.of(context)`.

7. IF a `BorderRadius.circular(N)` literal is intentionally retained in a migrated file (e.g., a platform-widget workaround or a hard constraint imposed by a third-party widget), THEN THE source line SHALL carry an inline comment beginning with `// ZETA-MIGRATION-EXEMPT:` followed by a one-sentence explanation. Lines with this annotation are exempt from the absence invariant grep check.

#### Correctness Property

**Minimum-radius invariant — no token-covered radius falls below `radiusSm`:**
For every `BorderRadius.circular(r)` call in migration-covered files that is not annotated with `// ZETA-MIGRATION-EXEMPT:`, the resolved value of `r` SHALL be greater than or equal to `NmtkShellTokens.radiusSm` (12). This is verifiable as a lint rule or a property test scanning the AST of migrated files for `BorderRadius.circular` nodes and asserting `r >= 12`.

**Absence invariant — zero bare `BorderRadius.circular(N)` numeric literals in migration-covered files:**
After migration, a grep search for `BorderRadius\.circular\([0-9]` across `nmtk_ui_core/lib/widgets/`, `surface_card.dart`, `summary_card.dart`, `pipeline_stepper.dart`, `validation_chip.dart`, `workflow_step_row.dart`, `info_chip.dart`, and `workspace_shell.dart` SHALL return zero matches that are not followed by `tokens.` or annotated with `// ZETA-MIGRATION-EXEMPT:`.

**Symmetry property — `EdgeInsets.fromLTRB` is absent from workspace_shell:**
A grep search for `EdgeInsets\.fromLTRB` in `workspace_shell.dart` SHALL return zero matches after migration.

---

## Out of Scope

The following items were identified during the audit but are explicitly deferred:

- **Shell token value drift** (6 color values in `NmtkShellTokens.fromColorScheme` that diverge slightly from `DESIGN.md`): noted as a sub-task for a follow-up token-alignment pass.
- **Model-layer status colors** in `pynq_deployment_model` and `akida_deployment_model`: architectural concern deferred pending a model-layer design review.
