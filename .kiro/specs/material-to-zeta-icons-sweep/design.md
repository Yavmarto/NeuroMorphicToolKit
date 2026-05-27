# Design Document — material-to-zeta-icons-sweep

## Overview

Three-tier sweep across six Flutter packages (631 hits, 112 files, 263 distinct icon names). Tier A is mechanical via normalisation rules. Tier B is a curated semantic mapping table reviewed once and applied uniformly. Tier C1 retains residual `Icons.*` calls with an explicit marker comment that the governance test counts.

## Tier A — Normalisation rules

Applied in order. The first rule that yields a hit in `ZetaIcons` is the chosen replacement.

| # | Rule | Example |
|---|---|---|
| 1 | Replace trailing `_outlined` with `_outline` | `Icons.error_outlined` → `ZetaIcons.error_outline` |
| 2 | Drop trailing `_rounded` | `Icons.refresh_rounded` → `ZetaIcons.refresh` |
| 3 | Drop infix `_amber` | `Icons.warning_amber_rounded` → `ZetaIcons.warning` |
| 4 | Append `_round` to the result of 1–3 | `Icons.arrow_back_rounded` → `ZetaIcons.arrow_back_round` |

Lossy normalisations are acceptable. `Icons.warning_amber_rounded → ZetaIcons.warning` loses the amber colour cue; the colour is reapplied by setting `Icon(...).color = tokens.warningColor` from `NmtkShellTokens`.

Estimated coverage: **108 distinct icons / 335 call sites** (51 % of total).

## Tier B — Curated semantic mapping

Each row reviewed once during T-ICON-4 and applied uniformly across all six packages. Rows below are the starter set; the table is appended to as new Tier B candidates are discovered.

| Material | Zeta replacement | Visual delta | Notes |
|---|---|---|---|
| `play_arrow`, `play_arrow_rounded`, `play_arrow_outlined` | `ZetaIcons.play` | Triangle → triangle-in-circle | Acceptable |
| `play_circle_outline`, `play_circle_outline_rounded` | `ZetaIcons.play_outline` | None | |
| `play_circle_fill`, `play_circle_fill_rounded` | `ZetaIcons.play_circle` | None | |
| `pause_circle_outline`, `pause_circle_outline_rounded` | `ZetaIcons.pause_outline` | None | Verify Zeta has `pause_outline` |
| `replay_circle_filled_rounded` | `ZetaIcons.replay` | Loses circle background | Acceptable |
| `arrow_back_ios_new_rounded` | `ZetaIcons.arrow_back` | iOS chevron → standard arrow | Acceptable |
| `arrow_forward_ios` | `ZetaIcons.arrow_forward` | iOS chevron → standard arrow | Acceptable |
| `arrow_drop_down` | `ZetaIcons.arrow_down` | None | |
| `keyboard_arrow_down` | `ZetaIcons.arrow_down` | None | |
| `keyboard_tab` | `ZetaIcons.arrow_forward` | Different glyph | Acceptable |
| `more_vert` | `ZetaIcons.more_vertical` | Rename only | |
| `info_outline`, `info_outline_rounded` | `ZetaIcons.info` | None (Zeta default round = outline-ish) | Verify visually |
| `circle_outlined` | `ZetaIcons.radio_button_outlined` | None | Used as bullet |
| `circle` | `ZetaIcons.radio_button_filled` | None | |
| `check` | `ZetaIcons.tick` | Same shape | Verify name in 1.9.3 |
| `open_in_new`, `open_in_new_rounded`, `open_in_browser` | `ZetaIcons.open_in_new_window` | Rename only | |
| `description`, `description_outlined` | `ZetaIcons.text_snippet` | Document → snippet glyph | Acceptable |
| `delete_outline`, `delete_outline_rounded` | `ZetaIcons.delete` | None | |
| `save_as_rounded` | `ZetaIcons.save` | Loses "as" affordance | Acceptable |
| `folder_open_outlined`, `folder_open_rounded` | `ZetaIcons.folder_outline` | Loses "open" affordance | Acceptable |
| `file_open_outlined` | `ZetaIcons.file_outline` | Loses "open" affordance | Acceptable |
| `insert_drive_file_outlined` | `ZetaIcons.file_outline` | Same glyph family | |
| `attach_file_rounded` | `ZetaIcons.attachment` | None | Verify name |
| `download_for_offline_outlined` | `ZetaIcons.download` | Loses circle border | Acceptable |
| `pause_circle_outline`, `pause_circle_outline_rounded` | `ZetaIcons.pause_outline` | None | |
| `fiber_manual_record`, `fiber_manual_record_rounded` | `ZetaIcons.radio_button_filled` | Same shape, semantic match | |
| `unfold_more` | `ZetaIcons.expand_vertical` | Verify name | |
| `view_stream` | `ZetaIcons.list_bullet` | Different glyph | Acceptable |
| `show_chart` | `ZetaIcons.line_chart` | None | Verify name |
| `multiline_chart_rounded` | `ZetaIcons.line_chart` | None | |
| `bar_chart_rounded` | `ZetaIcons.chart_bar` | None | |
| `data_usage_rounded` | `ZetaIcons.chart_doughnut` | None | |
| `equalizer` | `ZetaIcons.chart_bar` | Approximate | Acceptable |
| `graphic_eq_rounded` | `ZetaIcons.activity` | Approximate | Acceptable |
| `linear_scale` | `ZetaIcons.minus` | Different glyph | Acceptable |
| `square_rounded` | `ZetaIcons.stop` | Square shape match | |
| `panorama_horizontal_outlined` | `ZetaIcons.image` | Approximate | Acceptable |
| `videocam_off_outlined` | `ZetaIcons.video_off` | Verify name | |
| `usb_off_rounded` | `ZetaIcons.power_off` | Approximate | Acceptable |
| `wifi_find_rounded` | `ZetaIcons.wifi` | Loses "find" affordance | Acceptable |
| `cloud_off` | `ZetaIcons.cloud_offline` | Verify name | |
| `cloud_upload_outlined` | `ZetaIcons.upload_cloud` | Verify name | |
| `do_not_disturb_alt_outlined` | `ZetaIcons.block` | Same semantic | |
| `block` | `ZetaIcons.block` | Already used in app theme | |
| `web`, `web_outlined`, `web_rounded` | `ZetaIcons.globe` | Globe glyph | Acceptable |
| `language_outlined` | `ZetaIcons.globe` | Same | |
| `notes_rounded` | `ZetaIcons.text_snippet` | None | |
| `sticky_note_2_outlined` | `ZetaIcons.note` | Verify name | |
| `text_snippet_outlined` | `ZetaIcons.text_snippet` | None | |
| `article`, `article_outlined` | `ZetaIcons.article` if exists else `text_snippet` | | |
| `system_update` | `ZetaIcons.upgrade` | Verify name | |
| `sync_problem` | `ZetaIcons.sync_disabled` | Approximate | Acceptable |
| `link_off` | `ZetaIcons.link_disabled` | Verify name | |
| `search_off` | `ZetaIcons.search_disabled` | Verify name | |
| `filter_alt_off_rounded` | `ZetaIcons.filter` + style | Lose "off" | Acceptable |
| `filter_none` | `ZetaIcons.crop_square` | Approximate | Acceptable |

Estimated additional coverage: **~30 distinct icons / ~70 call sites**.

## Tier C1 — Residual Material with marker

Every remaining `Icons.X` call MUST be annotated with `// ZETA-MIGRATION-EXEMPT: <reason>` either on the same line (trailing) or on the line immediately preceding the `Icons.` reference.

```dart
// Pattern A — trailing marker
Icon(Icons.science_outlined,
     // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (scientific flask)
     color: tokens.metadataForeground)

// Pattern B — preceding marker on its own line
// ZETA-MIGRATION-EXEMPT: no Zeta equivalent (graph hub icon)
const Icon(Icons.hub_outlined, size: 20)
```

Stems with no Zeta equivalent (must be exempted): see §B of the scope doc — 112 distinct stems including `hub`, `account_tree`, `code`, `bolt`, `science`, `inventory_2`, `insights`, `compare_arrows`, `monitor_heart`, `architecture`, `extension`, `terminal`, `equalizer`, `functions`, `dashboard_customize`, `auto_awesome`, `auto_fix_high`, `model_training`, `rocket_launch`, `precision_manufacturing`, `widgets`, `developer_board`, `dns`, `api`, etc.

Estimated residual: **~125 distinct icons / ~225 call sites**.

## Import strategy

`ZetaIcons` is exported from `package:zeta_flutter/zeta_flutter.dart`, which is already imported (directly or via `package:nmtk_ui_core/nmtk_ui_core.dart`) in nearly every modified file because of T-UI-9. Before modifying a file, check:

```bash
grep -E "package:(zeta_flutter|nmtk_ui_core)" <file>
```

If neither import is present, add `import 'package:zeta_flutter/zeta_flutter.dart';` to the import block.

Material `Icons.X` requires `import 'package:flutter/material.dart';`. This import is unaffected — most files already have it for layout primitives. Tier C1 leaves the import in place.

## Governance test pattern

The same shape as `neurocnl/frontend/test/governance/zeta_first_audit_test.dart` (the `ChoiceChip` allowlist test), but with a baseline ratchet:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// Baseline ratchet — decrease as the T-ICON sweep progresses.
// At T-ICON-2 introduction, baseline equals the current grandfathered hit count.
// At T-ICON-6 completion, baseline must equal 0 and the test reduces to
// `icons_hits == marker_count`.
const int kIconsBaseline = <CURRENT_HIT_COUNT>;

void main() {
  test('Material Icons.* is forbidden in lib/ except with ZETA-MIGRATION-EXEMPT', () {
    final hits = _scanForToken('Icons.');
    final markers = _countMarkers(RegExp(r'ZETA-MIGRATION-EXEMPT:\s*\S'));
    expect(
      hits.length - markers,
      lessThanOrEqualTo(kIconsBaseline),
      reason: '...',
    );
  });
}
```

Per-package baselines at T-ICON-2 introduction:

| Package | `kIconsBaseline` |
|---|---:|
| `neurocnl/frontend` | 316 |
| `nmtk/neuro_toolkit` | 84 |
| `Neurohub/frontend` | 64 |
| `Neurosense/frontend` | 60 |
| `nmtk_ui_core` | 59 |
| `Neurobench/frontend` | 48 |

## File order (descending hit count)

Sweep files in this order within each package. After each file: `dart analyze <file>`. After each package: `flutter test <package>/`.

### neurocnl/frontend (316 hits, 52 files)

Top files:
1. `lib/widgets/simulator_panel.dart` — 22 hits
2. `lib/widgets/export_menu.dart` — 21 hits
3. `lib/screens/studio/compiled_artifacts/compiled_artifacts_panel.dart` — 18 hits
4. `lib/widgets/cnl_sentence_builder_dialog.dart` — 18 hits
5. `lib/screens/analysis_screen.dart` — 17 hits
6. `lib/screens/server_setup_screen.dart` — 17 hits
7. `lib/screens/canvas/canvas_screen.dart` — 16 hits
8. `lib/providers/canvas/nir_types_provider.dart` — 15 hits
9. `lib/widgets/network_graph_view.dart` — 14 hits
10. `lib/widgets/nir_importer_tab.dart` — 14 hits
... (remaining 42 files in descending hit order)

### nmtk/neuro_toolkit (84 hits, 11 files)

Top files:
1. `lib/widgets/module_picker_panel.dart` — 38 hits
... (remaining 10 files in descending hit order)

### Neurohub/frontend (64 hits, 12 files)

Top files:
1. `lib/screens/asset_library_screen.dart` — 15 hits
2. `lib/screens/project_detail_screen.dart` — 13 hits
3. `lib/screens/bundle_inspection_screen.dart` — 13 hits
... (remaining 9 files in descending hit order)

### Neurosense/frontend (60 hits, 12 files)

Top files:
1. `lib/app.dart` — 18 hits
2. `lib/widgets/signal_quality_bar.dart` — 12 hits
... (remaining 10 files in descending hit order)

### nmtk_ui_core (59 hits, 15 files)

Top files:
1. `lib/widgets/desktop_scaffold.dart` — 27 hits
2. `lib/models/shell_models.dart` — 5 hits
3. `lib/models/pynq_deployment_model.dart` — 5 hits
4. `lib/models/akida_deployment_model.dart` — 5 hits
5. `lib/widgets/pipeline_stepper.dart` — 5 hits
... (remaining 10 files)

> Special handling: the four model files in `nmtk_ui_core/lib/models/` and `pipeline_stepper.dart` expose `IconData` constants as public API. Type stays `IconData`; only constant values change. Add the regression test required by REQ-6.2.

### Neurobench/frontend (48 hits, 10 files)

Top files:
1. `lib/screens/workbench_shell.dart` — 27 hits
... (remaining 9 files)

## Final verification (T-ICON-6)

```bash
grep -rE '\bIcons\.' --include='*.dart' \
  nmtk_ui_core/lib \
  neurocnl/frontend/lib \
  Neurohub/frontend/lib \
  Neurobench/frontend/lib \
  Neurosense/frontend/lib \
  nmtk/neuro_toolkit/lib | grep -v 'ZETA-MIGRATION-EXEMPT'
```

Must return zero hits. All six governance tests pass with `kIconsBaseline = 0`.
