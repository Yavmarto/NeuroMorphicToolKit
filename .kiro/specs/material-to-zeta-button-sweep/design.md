# Design Document: material-to-zeta-button-sweep

## Overview

A mechanical find-and-replace sweep across 45 Dart source files. No new abstractions are introduced. The change is purely a widget-type substitution — the visual output is already Zeta-styled since all app roots use `NmtkZetaTheme.wrap()`.

## Replacement Map

| Source pattern | Zeta replacement | Notes |
|---|---|---|
| `ElevatedButton(onPressed: X, child: Text(Y))` | `ZetaButton(onPressed: X, label: Y)` | |
| `ElevatedButton.icon(onPressed: X, icon: Icon(Z), label: Text(Y))` | `ZetaButton(onPressed: X, label: Y, leadingIcon: Z)` | Drop `styleFrom` |
| `ElevatedButton.styleFrom(backgroundColor: Colors.red*)` | `ZetaButton.negative(...)` | Red color intent |
| `ElevatedButton.styleFrom(backgroundColor: Colors.green*)` | `ZetaButton.positive(...)` | Green color intent |
| `TextButton(onPressed: X, child: Text(Y))` | `ZetaButton.text(onPressed: X, label: Y)` | |
| `TextButton.icon(onPressed: X, icon: Icon(Z), label: Text(Y))` | `ZetaButton.text(onPressed: X, label: Y, leadingIcon: Z)` | Drop `styleFrom` |
| `OutlinedButton(onPressed: X, child: Text(Y))` | `ZetaButton.outline(onPressed: X, label: Y)` | |
| `OutlinedButton.icon(onPressed: X, icon: Icon(Z), label: Text(Y))` | `ZetaButton.outline(onPressed: X, label: Y, leadingIcon: Z)` | Drop `styleFrom` |

## Loading State Pattern

```dart
// Before
ElevatedButton.icon(
  onPressed: isLoading ? null : onTap,
  icon: isLoading
      ? const SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2))
      : const Icon(Icons.play_arrow),
  label: Text(isLoading ? 'Running…' : 'Run'),
  style: ElevatedButton.styleFrom(...),
)

// After — ZetaButton.leadingIcon takes IconData, not Widget.
// Pass null for leadingIcon during loading:
ZetaButton(
  onPressed: isLoading ? null : onTap,
  label: isLoading ? 'Running…' : 'Run',
  leadingIcon: isLoading ? null : Icons.play_arrow,
)
```

## Import Strategy

Most files already import `nmtk_ui_core` which re-exports `ZetaButton`. Before modifying a file, check:

```
grep "nmtk_ui_core\|zeta_flutter" <file>
```

If neither is present, add `import 'package:zeta_flutter/zeta_flutter.dart';`.

## File Order (descending hit count)

### Task 5 — neurocnl/frontend (52 hits, 18 files)
1. `lib/screens/analysis_screen.dart` — 7 hits
2. `lib/screens/studio_screen.dart` — 6 hits
3. `lib/screens/canvas/canvas_screen.dart` — 6 hits
4. `lib/screens/hardware_screen.dart` — 6 hits
5. `lib/screens/server_setup_screen.dart` — 4 hits
6. `lib/widgets/hardware_connection_panel.dart` — 4 hits
7. `lib/widgets/simulator_panel.dart` — 3 hits
8. `lib/routing/app_router.dart` — 2 hits
9. `lib/widgets/akida_deploy_panel.dart` — 2 hits
10. `lib/widgets/error_boundary.dart` — 2 hits
11. `lib/widgets/cnl_editor.dart` — 2 hits
12. `lib/widgets/pynq_deploy_panel.dart` — 2 hits
13. `lib/widgets/teensy_deploy_panel.dart` — 1 hit
14. `lib/widgets/shell_surface.dart` — 1 hit
15. `lib/widgets/nir_importer_tab.dart` — 1 hit
16. `lib/widgets/canvas/simulation_control_panel.dart` — 1 hit
17. `lib/widgets/canvas/canvas_cnl_editor.dart` — 1 hit
18. `lib/widgets/template_gallery.dart` — 1 hit

### Task 6 — Neurohub/frontend (20 hits, 11 files)
1. `lib/screens/asset_library_screen.dart` — 6 hits
2. `lib/screens/login_screen.dart` — 4 hits
3. `lib/widgets/onboarding_tour.dart` — 2 hits
4. `lib/screens/project_detail_screen.dart` — 1 hit
5. `lib/screens/share_model_screen.dart` — 1 hit
6. `lib/screens/new_project_screen.dart` — 1 hit
7. `lib/screens/settings_screen.dart` — 1 hit
8. `lib/screens/bundle_inspection_screen.dart` — 1 hit
9. `lib/screens/live_test_screen.dart` — 1 hit
10. `lib/screens/feed_screen.dart` — 1 hit
11. `lib/screens/my_shares_screen.dart` — 1 hit

### Task 7 — Neurobench/frontend (14 hits) + Neurosense/frontend (5 hits)

Neurobench:
1. `lib/screens/workbench_shell.dart` — 10 hits
2. `lib/screens/comparison_screen.dart` — 2 hits
3. `lib/screens/regression_trends_screen.dart` — 1 hit
4. `lib/widgets/results_summary_card.dart` — 1 hit

Neurosense:
1. `lib/widgets/export_dialog.dart` — 2 hits
2. `lib/widgets/spike_encoding_panel.dart` — 1 hit
3. `lib/widgets/signal_quality_bar.dart` — 1 hit
4. `lib/widgets/live_signal_viewer.dart` — 1 hit

### Task 8 — nmtk/neuro_toolkit (13 hits, 8 files)
1. `lib/screens/settings.dart` — 4 hits
2. `lib/routing/router.dart` — 2 hits
3. `lib/widgets/module_picker_panel.dart` — 2 hits
4. `lib/screens/python_setup.dart` — 1 hit
5. `lib/screens/server_setup.dart` — 1 hit
6. `lib/screens/backend_setup.dart` — 1 hit
7. `lib/widgets/module_error_view.dart` — 1 hit
8. `lib/widgets/module_loading_view.dart` — 1 hit

## Final Verification

After Task 8, run this grep across all 5 `lib/` directories — must return zero hits:

```bash
grep -r 'ElevatedButton\b\|TextButton\b\|OutlinedButton\b' \
  neurocnl/frontend/lib \
  Neurohub/frontend/lib \
  Neurobench/frontend/lib \
  Neurosense/frontend/lib \
  nmtk/neuro_toolkit/lib \
  --include='*.dart'
```

Note: `nmtk_ui_core/lib/app_theme.dart` may still reference these in ThemeData construction — that is not a widget call site and is excluded from this sweep.
