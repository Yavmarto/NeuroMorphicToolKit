# NMTK Flutter Frontend Audit — Full Suite Sweep

Scope: all 6 Flutter surfaces in the monorepo — `nmtk_ui_core` (shared design-system library), `neurocnl/frontend` (CNL Studio), `Neurohub/frontend`, `Neurosense/frontend`, `Neurobench/frontend`, `nmtk/neuro_toolkit` (Launcher). `Neurochip/frontend` has no Flutter code yet (IDE stub only) and was excluded.

Read-only audit. No files were modified. `flutter analyze` / `flutter test` were run per module (read-only) to get objective pass/fail evidence alongside the manual design-system review.

---

## Module Scorecard

| Module | Design System | Build (`analyze`) | Tests | Worst finding |
|---|---|---|---|---|
| `nmtk_ui_core` | FAIL | clean | not run per-file group | Shared library — every violation here propagates to all 5 consumer modules |
| `Neurohub/frontend` | FAIL (1/4) | clean (1 unrelated test-file warning) | **5 failing** | 4 screens with zero shell mode; mobile dashboard silently drops shell mode → real overflow bug |
| `Neurosense/frontend` | FAIL (1/4) | **4 real compile errors** | **8 test files fail to compile** | Build is broken: `ZetaButton` called with nonexistent params, missing import |
| `Neurobench/frontend` | FAIL (2/4) | clean | clean (39 pass, 3 skip) | Only module with a fully green build+test; still 9 raw radius literals + dead-code shell violations |
| `neurocnl/frontend` (428 files, largest) | FAIL (1/4) | **2 real compile errors** | 4 failures (3 flaky async race + 1 layout) | `TextEditingController` leak on the primary NeuroSim canvas; no `NmtkDesktopScaffold`/`NmtkTopAppBar` anywhere despite AGENTS.md mandate |
| `nmtk/neuro_toolkit` (Launcher) | FAIL (3/4) | clean (2 info-lints) | **2 failing** | Populated workspace view loses Settings access entirely (confirmed by failing test); wrong hardcoded port breaks connectivity |

**Bottom line: every module fails the design-system gate, and 4 of 6 modules currently have a red `flutter test` run.** Two modules (`Neurosense`, `neurocnl`) have real `flutter analyze` compile errors, not just lints.

---

## Cross-Suite P0 — fix these first (ranked by user impact)

1. **Neurosense build is broken** — `lib/widgets/device_selector.dart:96`, `lib/widgets/recording_controls.dart:126,130,187` call `ZetaButton` with a `tone`/`icon` parameter that doesn't exist on the real widget (real param is `type: ZetaButtonType.*` / `leadingIcon`), and use `RecordingSession.formattedDuration/.formattedFileSize` without importing the extension that defines them (`models/session.dart`). 4 compile errors, cascades into 8 test files failing to build. **Nothing else in Neurosense matters until this compiles.**

2. **Launcher silently drops Settings access** — `nmtk/neuro_toolkit/lib/screens/tool_view.dart:829-856` (desktop) / `:809-826` (mobile): the populated-modules view (what users see almost all the time) renders a bare `Scaffold` with no `NmtkTopAppBar`/`NmtkShellMode.command` at all — `NmtkShellMode.command` is only ever set in the *empty*-modules branch (`tool_view.dart:728-741`). Mobile additionally passes `onSettingsPressed: null`, removing the only other path to Settings. Confirmed live by a currently-failing test (`test/tool_view_shell_test.dart:116`).

3. **Launcher saves the wrong control-API port** — `nmtk/neuro_toolkit/lib/services/control_api_service.dart:131`: `normalizeBaseUrl` appends hardcoded `:8091` when a user types a bare host, but the real default port is `8090` (`8091` is the unrelated Akida hardware-control port). This is persisted to SharedPreferences from the Settings screen — any user who follows the UI's own placeholder text (`192.168.1.50`, no port) gets silently pointed at the wrong service.

4. **neurocnl: `TextEditingController` leak on the primary canvas** — `lib/widgets/canvas/network_canvas.dart:721,755-762`: a controller is created for the stylus handwriting popup on every node-creation gesture and never disposed when the popup is dismissed.

5. **neurocnl: 2 real analyzer errors** — `lib/providers/cnl_line_node_map_provider.dart:28,31` — `undefined_method 'select'` on `PipelineControllerProvider`/`CanvasControllerProvider`. This branch does not compile clean.

6. **Neurohub: mobile dashboard overflow is a real, reproducing bug** — `lib/screens/dashboard_screen.dart:72-74`: the mobile branch falls back to a raw `AppBar` (no shell mode) instead of `NmtkTopAppBar`, and this exact code path is what's causing 2 of the 5 currently-failing tests (`RenderFlex overflowed by 540333 pixels`).

7. **nmtk_ui_core: `NmtkDesignTokens.dialogShape` is wrong in its own definition** — `nmtk_ui_core/lib/app_theme.dart:19`: defines the dialog radius as `20.0`, but the suite-wide spec (and this skill's own token table) says dialogs must be `28`. Every consumer trusting this "canonical" token is silently non-compliant.

8. **nmtk_ui_core: hardcoded status-color hex baked into shared models** — `nmtk_ui_core/lib/models/akida_deployment_model.dart:287-300` and `nmtk_ui_core/lib/models/pynq_deployment_model.dart:71-84` hardcode 5 raw hex values each for deployment-status semantics, bypassing `NmtkShellTokens` entirely — and these models feed color into `pynq_deploy_status_card.dart`, so the violation propagates into a widget that otherwise looks compliant.

9. **nmtk_ui_core: systemic status-color bypass** — `loading_screen.dart`, `progress_card.dart`, `pynq_deploy_status_card.dart`, `quantization_table.dart`, `workflow_card.dart`, `toasts.dart` all source health/error/warning color from `Zeta.of(context).colors.mainPositive/mainNegative/mainWarning` (or raw `theme.colorScheme.error`) instead of the mandated `NmtkShellTokens.healthyColor/errorColor/warningColor` — only `pipeline_stepper.dart` does this correctly in the whole package.

---

## Per-Module Detail

### nmtk_ui_core (shared library — 97 files, highest leverage)
**Design System Score: FAIL** — border radius: FAIL (9 raw literals incl. wrong `dialogShape` constant) / status colours: FAIL (systemic — see P0 #8-9) / zeta compliance: FAIL (raw `Chip`/`IconButton`/`TextField`/`SnackBar`/`Tooltip` used where `ZetaChip`/`ZetaIconButton`/`ZetaSearchBar`/`ZetaSnackBar`/`ZetaTooltip` exist) / nmtk_ui_core boundary (no state-mgmt imports): **PASS**, verified clean across all 97 files / barrel export: **PASS**, everything public is exported.

P0:
- `app_theme.dart:17-20,417` — 5 raw-literal radii (16/24/20/12/12), including the wrong `dialogShape` value (P0 #7 above).
- `visualization/tile_grid_renderer.dart:147,228,241` — 3 more raw radii (10, 3×2).
- `models/akida_deployment_model.dart:287-300`, `models/pynq_deployment_model.dart:71-84` — hardcoded status hex (P0 #8).
- `widgets/status_badge.dart:34` — raw `999` instead of `radiusChip` token.
- `widgets/pipeline_stepper.dart:646` — raw `11`.
- Systemic status-color bypass across 6 widgets (P0 #9).
- Zeta-bypass: `backend_support_banner.dart:96,114`, `command_palette.dart:143`, `desktop_scaffold.dart:506,834,904`, `energy_bar_chart.dart:178`, `toasts.dart` (whole file, no zeta_flutter import), `top_app_bar.dart:107-122`, `workspace_switcher_bar.dart:197-238`, `mobile_scaffold.dart:282` (unmarked raw `Icons.menu_rounded`), `pipeline_stepper.dart:291,300,318` (unmarked raw `Icons.remove/add`), `key_value_row.dart` (whole file has zero Zeta integration), `tile_grid_renderer.dart:84` (`Colors.white` where `zetaColors.mainInverse` was used two lines later in the same file).
- Custom `BoxShadow` on a plain container in `pipeline_stepper.dart:648-655` — explicitly banned by the "No Visual Gimmicks" rule.

P1 (selected, ~20 total across sub-audits):
- `renderer_registry.dart:23` — empty catch, no logging.
- `widgets/summary_card.dart:22`, `widgets/info_chip.dart:20-22`, `widgets/validation_chip.dart:183-185,289-291` — empty/bare catch blocks around `Zeta.of(context)`.
- Multi-widget-class files: `desktop_scaffold.dart` (11 classes), `motion_tokens.dart` (3), `command_palette.dart` (3), `energy_bar_chart.dart` (3), `section_header.dart` (2), `shell_readiness_state_view.dart` (2), `pipeline_stepper.dart` (4), `mobile_scaffold.dart` (3), `loading_screen.dart` (6), `quantization_table.dart` (2), `top_app_bar.dart` (2), `validation_chip.dart` (3), `workflow_card.dart` (2), `workspace_switcher_bar.dart` (2).
- Oversized `build()`: `command_palette.dart` (~184 lines), `akida_support_state_card.dart` (~109), `workspace_switcher_bar.dart` `NmtkWorkspaceChip.build()` (162), `surface_card.dart` (116), `top_app_bar.dart` (105), `validation_chip.dart` (103).
- Hardcoded domain strings with no override param: `app_theme.dart:424` (`'NMTK Hub'` title), `tile_grid_renderer.dart:156-171` (core/neuron labels), `snn_workflow_stepper.dart:115-158` + `snn_mobile_workflow_stepper.dart:31-39` (7 SNN pipeline-stage labels, duplicated in two files), `akida_support_state_card.dart:82`, `pipeline_stepper.dart:292,301,319,175` (tooltips/semantics label), `mobile_scaffold.dart:117-296` (7 action-sheet strings), `workspace_switcher_bar.dart:198-224` (3 tooltips).

### Neurohub/frontend (41 files; task cited 71 — verified 41 actually exist)
**Design System Score: 1/4** — border radius: FAIL / status colours: PASS / shell mode: FAIL / zeta compliance: FAIL.

`flutter analyze`: clean (1 unrelated test-file warning). `flutter test`: **55 pass, 5 fail** — 2 shell-adapter deep-link tests, 2 mobile-overflow tests, 1 text-mismatch test, all tracing back to the same root cause (P0 #6 above).

P0: `login_screen.dart:68`, `register_screen.dart:66`, `settings_screen.dart:11`, `live_test_screen.dart:11` — 4 screens with a raw `AppBar`, zero `NmtkShellMode`; `dashboard_screen.dart:72-74` mobile branch same issue (causes the test failures); raw `TextField`/`DropdownButtonFormField`/`SwitchListTile` instead of Zeta equivalents (`dashboard_screen.dart:81-106`, `share_model_screen.dart:196-226`, `asset_library_screen.dart:320-335`); `project_detail_screen.dart:198` raw radius `16`.

P1: 3 files with extra un-excepted widget classes (`asset_library_screen.dart`, `bundle_inspection_screen.dart`, `feed_screen.dart`); `Navigator.push` used in 4 places instead of `context.go()` — and the module has **no `go_router` dependency at all**, a structural gap, not just scattered call sites; 2 empty catch blocks in `neurohub_workspace_controller.dart:63-68,76-81`.

P2: 8 dead/unused widgets never instantiated in `lib/` (`config_panel.dart`, `live_test_dashboard.dart`, `member_manager.dart`, `milestone_timeline.dart`, `note_editor.dart`, `workflow_step_card.dart`, `bundle_export_dialog.dart`, `asset_card.dart`, `onboarding_tour.dart`); unused codegen deps (`freezed`/`riverpod_generator` declared, never used); one screen bypasses the DI provider and constructs `ApiService()` directly.

### Neurosense/frontend (52 files: 34 hand-written + 18 generated)
**Design System Score: 1/4** — border radius: FAIL / status colours: PASS / shell mode: **PASS** / zeta compliance: FAIL.

`flutter analyze`: **4 real compile errors in `lib/`** (see P0 #1). `flutter test`: 40 pass, **8 test files fail to compile** — all trace to the same 4 lines.

P0 (beyond the build breakage): `replay_controls.dart:372,380` and `live_signal_viewer.dart:281` raw radii (12, 999); `spike_encoding_panel.dart:126` hardcoded `Colors.white`; raw Material `Chip` used in place of the module's own `NmtkStatusBadge` in 5 files; module's own `AGENTS.md` explicitly requires `LiveSignalViewer` to use `Expanded`, never a hardcoded pixel height — `live_signal_viewer.dart:16` defaults to a hardcoded `240` and the mobile screen branch uses that default.

P1: `app.dart` `build()` ~213 lines; `replay_controls.dart` 600 lines / 8 classes; 2 empty catch blocks in `neurosense_workspace_controller.dart:50,64` around restoration/deep-link parsing, no logging; widespread `Theme.of(context).textTheme.*` instead of Zeta text styles (9 files); raw `SwitchListTile`/`AlertDialog`/`Slider` with no `ZETA-MIGRATION-EXEMPT` documentation (unlike the icon exemptions used consistently elsewhere).

Note: no dispose leaks found anywhere in this module — all controllers/subscriptions/timers correctly paired.

### Neurobench/frontend (42 files; task cited 62 — verified 42 actually exist)
**Design System Score: 2/4** — border radius: FAIL / status colours: **PASS** / shell mode: **PASS** / zeta compliance: FAIL.

`flutter analyze`: clean, 0 issues. `flutter test`: clean, 39 pass, 3 skipped. **The only module with a fully green build and test suite.**

P0: 9 raw border-radius literals across 9 widget files (none of the explicitly-banned 8/10/14/18 values except `target_comparison_grid.dart:194`'s `Radius.circular(8)`; the rest are un-tokenized 12s/999s/3s/4s).

P1: pervasive `theme.textTheme.X` instead of `Zeta.of(context).textStyles.X` — 23 occurrences across 8 files, the single largest zeta-compliance gap found in this module; raw `Card`/`Chip`/`TextButton`/`Checkbox`/`CheckboxListTile`/`DropdownButtonFormField` where Zeta equivalents exist (10+ sites); 6 files with extra un-excepted widget classes; `workbench_shell.dart` `build()` ~180 lines; two entire screens (`comparison_screen.dart`, `regression_trends_screen.dart`) are **dead code** (unreachable via the router) yet still carry raw `Scaffold`/no-shell-mode/hybrid-`Navigator` violations — recommend deleting or re-wiring; `benchmarks_provider.dart:140-144` swallows fetch errors into the same `null` as "nothing selected yet," masking real backend outages behind a generic empty state.

P2: duplicated accuracy-tier color-threshold logic in 2 files (style guide explicitly bans duplicated status checks); `AlertDialog` missing explicit `shape: NmtkDesignTokens.dialogShape` (currently only correct by coincidence with the Material 3 default).

### neurocnl/frontend (428 files — largest module, Studio/NeuroSim canvas)
**Design System Score: 1/4** — border radius: FAIL (~90 raw literals across ~40 files) / status colours: FAIL (dozens of hardcoded hex, including one duplicating `warningColor`'s exact hex) / shell mode: PASS-with-caveat (`NmtkShellMode.studio` is hardcoded correctly in `shell_surface.dart:22`, but `NmtkDesktopScaffold`/`NmtkTopAppBar` are never used anywhere — the module's `AppShell` in `app_router.dart:182-215` renders a bare `Scaffold` instead, contradicting the literal AGENTS.md instruction even though the violet-accent visual intent is achieved) / zeta compliance: FAIL (162 manual `TextStyle(` call sites across 36 files; raw `Checkbox`/`TextButton`/`OutlinedButton`/`Card` in 20+ sites).

`flutter analyze`: **43 issues, 2 real errors** (`cnl_line_node_map_provider.dart:28,31`, see P0 #5) plus `invalid_use_of_protected_member` warnings from calling `setState` via an extension on private state (`workspace_file_io.dart:80,129` — functions today but violates the state-mutation-boundary rule). `flutter test`: 1408 run, 4 failures — 3 are a genuine async race in `simulator_preflight_provider_test.dart` (property-based tests non-deterministically observe `.idle` instead of `.success`), 1 is a layout overflow + dispose-ordering bug in `studio_screen_test.dart`.

P0 highlights: `TextEditingController` leak on the primary canvas (P0 #4); the ~90 raw-radius violations include the explicitly-banned 18/14/10/8 values in `network_graph_view.dart`, `pipeline_overview_canvas.dart`, `canvas_screen.dart`, `pipeline_phase_canvas.dart`; hardcoded hex category-colors are copy-pasted verbatim across 3 separate files (`canvas_screen.dart`, `pipeline_phase_canvas.dart`, `pipeline_palette.dart`) with no shared constant — a DRY violation on top of the token violation; `cnl_line_highlight_painter.dart:46` hardcodes the exact hex of `NmtkShellTokens.warningColor` instead of referencing it.

P1: `project_screen.dart:213-214` — 2 more undisposed `TextEditingController`s; 6+ empty/bare catch blocks in the CNL↔NIR sync and preflight paths, most severely `nir_import_provider.dart:187-192` silently dropping malformed NIR payloads with zero diagnostics; several genuinely massive files — `simulator_panel.dart` (1679 lines, 20 widget classes), `network_canvas.dart` (2165 lines), `training_inspector_panel.dart` (817 lines, 10 classes), `studio_screen.dart` (1220 lines), `setup_step.dart` (1650 lines, 8 classes).

### nmtk/neuro_toolkit (Launcher, 67 files: 50 hand-written + 17 generated)
**Design System Score: 3/4** — border radius: **PASS** (only 4 call sites in the whole app, all tokenized) / status colours: **PASS** (zero hardcoded hex; routes through `nmtk_ui_core`'s `NmtkStatusBadge`/`NmtkTone`) / shell mode: **FAIL** (see P0 #2) / zeta compliance: PASS with minor nits.

`dart analyze`: clean, 2 info-lints only. `flutter test`: 65 pass, **2 fail** — `tool_view_shell_test.dart` (confirms P0 #2) and `analytics_test.dart` (pre-existing, unrelated `PathProviderPlatform` mock gap).

P0: the shell-mode/Settings-access regression (#2) and the wrong hardcoded port (#3) — both are real functional bugs with concrete user impact, not style nits.

P1: `tool_view.dart` `build()` ~211 lines; `widgets/tool_view_header_actions.dart` — a fully-built dev-mode/command-palette widget with **zero references anywhere in `lib/`**, almost certainly orphaned by the same regression that caused P0 #2; `tool_view.dart:32` hardcodes a module id (`'Neurobench'`) to hide it from mobile nav with no corresponding field in `modules.json` — the exact kind of manifest/code desync the project's own AGENTS.md calls out as a recurring mistake; `environment_editor.dart:210` — undisposed `TextEditingController` in a dialog helper; `workspace_notifier.dart:20-27` — swallows `fetchWorkspace()` failures silently, no logging, unlike sibling notifiers; `native_surface_registry.dart:14-37` — module-id string literals duplicated from `modules.json` with no test tying them together.

---

## What was NOT covered
- Golden/screenshot tests were not run in any module (out of scope for a read-only static+test audit).
- `dart fix --apply`/`dart format` were intentionally **not** run per instructions (read-only audit) — running them is a reasonable immediate next step in every module before hand-fixing the P0/P1 list above.
- Cross-module contract propagation (e.g. does `Neurohub`'s dead `go_router`-less routing matter for anything shared) was not chased beyond noting it.
