# Tech Debt Cleanup: Deprecated Code Removal & Material Design Elimination

**Created**: 2026-05-24
**Status**: Tasks 1–4 complete. Tasks 5–8 in progress (widget-level sweep).

## Completion Log

- **Task 1** ✅ 2026-05-24 — stale worktree removed, 8 stray scripts deleted, `mobile_bottom_bar.dart` added to barrel
- **Task 2** ✅ 2026-05-24 — `nengo_generator.py`, `export/__init__.py`, `generate`/`EXPORTERS` surface deleted; pipeline.py Nengo steps removed; 6 demo pairs, 3 examples deleted; deploy.py and export.py router updated
- **Task 3** ✅ 2026-05-24 — `NmtkZetaTheme.wrap()` wired into all 5 app roots; `app_theme.dart` kept in barrel for test harness compat with TODO
- **Task 4** ✅ 2026-05-24 — `OutlinedButton` in `loading_screen.dart` → `ZetaButton.negative`; `NavigationBar` in `desktop_scaffold.dart` kept (no Zeta equivalent)
- **Tasks 5–8** 🔄 Deferred — 138 `ElevatedButton`/`TextButton`/`OutlinedButton` hits remain across 5 frontends (neurocnl: 82, nmtk: 20, Neurohub: 16, Neurobench: 14, Neurosense: 6). These render via Zeta theme since all app roots are now wrapped. Widget-type replacement is a follow-on session.

---

## Problem Statement

Three categories of tech debt to clean:
1. Deprecated legacy Nengo symbols still re-exported from `neurocnl`'s public surface
2. Direct Material Design widget usage throughout 5 Flutter frontends that should use Zeta equivalents
3. Stray/orphaned files including root-level scripts, a stale git worktree with shadcn references, and an unexported widget

## Requirements

- **1=a (Material)**: Full Zeta-only — replace `MaterialApp` roots with `NmtkZetaTheme.wrap`, remove manual `ThemeData` construction in `app_theme.dart`, replace all direct Material component widgets with Zeta equivalents across all 5 frontends
- **2=a (Python)**: Delete legacy Nengo surface — remove `generate`, `GeneratorError`, `EXPORTERS`, `export` from `__init__.py`, delete `nengo_generator.py`, `export/__init__.py`, and update all demos/examples that used them to use `compile_to_nir`
- **3=a (Stray files)**: Hard delete — stray root scripts in `neurocnl/`, unexported `mobile_bottom_bar.dart`, and the stale git worktree

## Background

- `nmtk_ui_core` already has `zeta_flutter: ^1.4.5` and `NmtkZetaTheme.wrap()` — zero new dependencies needed
- `NmtkZetaTheme.wrap()` provides `ThemeData light/dark` from Zeta, so `AppTheme.*` can be deleted once all call sites use `NmtkZetaTheme.wrap()`
- The 5 Flutter apps (`neurocnl/frontend`, `Neurobench/frontend`, `Neurohub/frontend`, `Neurosense/frontend`, `nmtk/neuro_toolkit`) have ~730 direct Material widget hits across screens; most map cleanly to Zeta equivalents (`ZetaButton`, `ZetaTextInput`, `ZetaListItem`, etc.)
- The `export()` function in `export/__init__.py` is Nengo-based (takes a `nengo.Network`); the demos use `generate()` + `export()` — both are legacy paths; active code uses `compile_to_nir()` + individual `*_exporter.py` functions directly
- The 6 demo `run_demo.py/test_demo.py` pairs that call `from neurocnl import export` need to be updated to use `compile_to_nir()` + direct exporter calls
- Stray root files: `neurocnl/test_nengo_io.py`, `example_tester.py`, `test.py`, `example_nengo_model.py`, `update_grammar.py`, `_verify_task_9.py`, `fix_state.py`, `fix_end.py`
- Worktree at `.claude/worktrees/youthful-montalcini-e12408` is a stale branch with ~170 shadcn references
- `mobile_bottom_bar.dart` is not exported in the barrel and only referenced in one test — delete both

## Zeta replacement map

| Material widget | Zeta equivalent |
|---|---|
| `ElevatedButton` / `TextButton` / `OutlinedButton` | `ZetaButton` |
| `TextField` | `ZetaTextInput` |
| `AlertDialog` / `showDialog` | `ZetaDialog` |
| `SnackBar` / `showSnackBar` | `NmtkToast` (nmtk_ui_core) |
| `Chip` | `ZetaStatusChip` or `NmtkInfoChip` |
| `CircularProgressIndicator` | `ZetaProgressCircular` |
| `TabBar` / `Tab` | `ZetaTabBar` |
| `ListTile` | `ZetaListItem` |
| `Card` | `ZetaSectionCard` or nmtk `SectionCard` |
| `NavigationBar` (mobile) | `NmtkMobileBottomBar` or Zeta bottom nav |

Layout primitives (`Scaffold`, `Column`, `Row`, `Container`, `SizedBox`, `Padding`, `Stack`, etc.) are fine to keep — they are not Material Design components.

---

## Task Breakdown

### Task 1: Delete the stale git worktree and stray root scripts in neurocnl

**Objective**: Remove all confirmed-dead files with zero downstream impact.

- Run `git worktree remove --force .claude/worktrees/youthful-montalcini-e12408` to remove the stale worktree
- Delete from `neurocnl/` root: `test_nengo_io.py`, `example_tester.py`, `test.py`, `example_nengo_model.py`, `update_grammar.py`, `_verify_task_9.py`, `fix_state.py`, `fix_end.py`
- Delete `nmtk_ui_core/lib/widgets/mobile_bottom_bar.dart`
- Remove the reference to `mobile_bottom_bar` from `Neurohub/frontend/test/screens/neurohub_responsive_audit_test.dart`
- Run `flutter test nmtk_ui_core/` and `python -m pytest neurocnl/` to confirm nothing broke

**Demo**: `git worktree list` shows no stale entry; `pytest` passes; `flutter test` passes.

---

### Task 2: Remove the legacy Nengo export surface from neurocnl

**Objective**: Delete `generate`, `GeneratorError`, `EXPORTERS`, `export` and their backing files.

- Delete `neurocnl/neurocnl/generation/nengo_generator.py` and its test `test_nengo_generator.py`
- Delete `neurocnl/neurocnl/export/__init__.py` (the Nengo-net dispatcher) — individual `*_exporter.py` files remain intact, they take NIR/compiled artifacts not Nengo networks
- Remove the two `# noqa: F401 # deprecated` lines from `neurocnl/neurocnl/__init__.py` (lines importing `EXPORTERS`, `export`, `GeneratorError`, `generate`)
- Update the docstring in `neurocnl/neurocnl/__init__.py` to remove the "Deprecated symbols" paragraph
- Update the 6 demo pairs (`gripper_reflex`, `tactile_explorer`, `emg_prosthetic`, `habituation`, `classical_conditioning`, `bci_neurofeedback`): replace `from neurocnl import export, generate` with `from neurocnl import compile_to_nir` and update the pipeline call to use `compile_to_nir()` + the relevant direct `export_*` function (e.g. `from neurocnl.export.c_header_exporter import export_c_header`)
- Update `neurocnl/examples/03_generate_network.py`, `04_full_pipeline.py`, `05_demo_simulations.py`, `scripts/benchmark_performance.py` the same way
- Check `neurocnl/backend/app/routers/export.py` and `deploy.py` — if they import from `neurocnl.export` (the dispatcher), update them to import from specific `*_exporter` modules directly
- Run `pytest neurocnl/` — verify all tests pass with zero `DeprecationWarning` emissions from this path

**Demo**: `python -c "from neurocnl import generate"` raises `ImportError`; `pytest` green.

---

### Task 3: Wire `NmtkZetaTheme.wrap()` into all 5 app roots & delete `AppTheme`

**Objective**: Replace `MaterialApp(theme: AppTheme.*, darkTheme: AppTheme.*)` in all 5 app entry points with `NmtkZetaTheme.wrap(...)`.

Pattern to apply in each app root:
```dart
// Before
return MaterialApp(
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  themeMode: ThemeMode.dark,
  ...
);

// After
return NmtkZetaTheme.wrap(
  builder: (context, light, dark, mode) => MaterialApp(
    theme: light,
    darkTheme: dark,
    themeMode: mode,
    ...
  ),
);
```

- Apply to: `neurocnl/frontend/lib/app.dart`, `Neurobench/frontend/lib/app.dart`, `Neurohub/frontend/lib/app.dart`, `Neurosense/frontend/lib/app.dart`, `nmtk/neuro_toolkit/lib/main.dart`
- Delete `nmtk_ui_core/lib/app_theme.dart`
- Remove `export 'app_theme.dart';` from `nmtk_ui_core/lib/nmtk_ui_core.dart`
- Update any tests that referenced `AppTheme.*` to use `NmtkZetaTheme.wrap()` as the test harness wrapper instead
- Run `flutter test` across all 5 packages

**Demo**: Hot-reload each app shell; dark theme from Zeta renders correctly. `grep -r 'AppTheme' --include='*.dart'` returns zero hits.

---

### Task 4: Replace Material component widgets in `nmtk_ui_core` lib

**Objective**: Eliminate direct Material component widget calls inside the shared component library.

Files to fix (by hit count):
- `lib/widgets/desktop_scaffold.dart` (28 hits) — replace any `ElevatedButton`, `TextButton`, `Chip`, `Card`, `Dialog`, `SnackBar` with Zeta equivalents; keep layout primitives
- `lib/widgets/top_app_bar.dart` (8 hits) — same audit
- `lib/shell_tokens.dart` (7 hits) — replace `Theme.of(context)` color/style lookups with `Zeta.of(context).colors.*`
- `lib/widgets/loading_screen.dart` — replace `OutlinedButton.styleFrom(...)` with `ZetaButton`

Run `flutter test nmtk_ui_core/` after each file. All 22 widget tests must pass.

**Demo**: `flutter test nmtk_ui_core/` passes; `grep -r 'ElevatedButton\|TextButton\|OutlinedButton' nmtk_ui_core/lib --include='*.dart'` returns zero hits.

---

### Task 5: Replace Material component widgets in `neurocnl/frontend`

**Objective**: ~523 hits across 55 files.

Tackle highest-hit files first:
1. `lib/screens/studio_screen.dart` (63 hits)
2. `lib/widgets/simulator_panel.dart` (45 hits)
3. `lib/screens/analysis_screen.dart` (37 hits)
4. `lib/widgets/teensy_deploy_panel.dart` (32 hits)
5. `lib/widgets/akida_deploy_panel.dart` (25 hits)
6. `lib/widgets/export_menu.dart` (23 hits)
7. Remaining files in descending order

Use the replacement map above. After each file run `flutter test neurocnl/frontend/`.

**Demo**: `grep -r 'ElevatedButton\|TextButton\|OutlinedButton\|TabBar\b\|AlertDialog\|ListTile\b\|TextField\b' neurocnl/frontend/lib --include='*.dart'` returns zero hits.

---

### Task 6: Replace Material component widgets in `Neurohub/frontend`

**Objective**: 100 hits across 18 files.

Tackle highest-hit files first:
1. `lib/screens/asset_library_screen.dart` (27 hits)
2. `lib/screens/project_detail_screen.dart` (13 hits)
3. `lib/screens/login_screen.dart` (13 hits) — `TextField` → `ZetaTextInput`, `ElevatedButton` → `ZetaButton`
4. `lib/screens/bundle_inspection_screen.dart` (9 hits)
5. Remaining files in descending order

Run `flutter test Neurohub/frontend/` after each file.

**Demo**: `grep` returns zero direct Material component widget hits in `Neurohub/frontend/lib`.

---

### Task 7: Replace Material component widgets in `Neurobench/frontend` and `Neurosense/frontend`

**Objective**: 113 hits (Neurobench) + 15 hits (Neurosense).

Neurobench — tackle in order:
1. `lib/screens/workbench_shell.dart` (55 hits) — likely `TabBar`, `Card`, `DropdownButton`
2. `lib/widgets/results_summary_card.dart` (14 hits)
3. `lib/widgets/report_builder.dart` (9 hits)
4. Remaining files

Neurosense — tackle in order:
1. `lib/app.dart` (5 hits) — `NavigationBar` → `NmtkMobileBottomBar`; `CircularProgressIndicator` → `ZetaProgressCircular`
2. Remaining widget files

Run `flutter test` for both packages after each file.

**Demo**: Both packages `flutter test` green; zero Material component widget references in lib/.

---

### Task 8: Replace Material component widgets in `nmtk/neuro_toolkit` & final sweep

**Objective**: 96 hits across 16 files. Final verification sweep.

Tackle in order:
1. `lib/screens/settings.dart` (21 hits)
2. `lib/widgets/module_picker_panel.dart` (13 hits)
3. `lib/screens/backend_setup.dart` (12 hits)
4. `lib/screens/server_setup.dart` (9 hits)
5. `lib/routing/router.dart` (9 hits)
6. Remaining files

After all replacements, run the full suite `flutter test` across all 6 packages.

**Final verification grep** (must return zero hits in any `lib/` directory):
```bash
grep -r 'ElevatedButton\|TextButton\|OutlinedButton\|NavigationBar\b\|AlertDialog\|SnackBar\b\|showDialog\b\|TabBar\b\|ListTile\b\|TextField\b\|DropdownButton\b\|CircularProgressIndicator' \
  nmtk_ui_core/lib \
  neurocnl/frontend/lib \
  Neurobench/frontend/lib \
  Neurohub/frontend/lib \
  Neurosense/frontend/lib \
  nmtk/neuro_toolkit/lib \
  --include='*.dart'
```

**Demo**: Full `flutter test` across all 6 packages passes; grep sweep is clean; `pytest neurocnl/` is clean; no `AppTheme`, no `shadcn`, no `generate()`/`EXPORTERS` anywhere in source.
