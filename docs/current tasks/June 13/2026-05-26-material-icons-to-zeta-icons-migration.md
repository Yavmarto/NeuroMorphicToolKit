# Material Icons → ZetaIcons Migration — Scope

**Date**: 2026-05-26
**Status**: Approved and **prioritized to the front of the active queue**. Tier B mapping approach approved; Tier C strategy is **C1 (keep Material with `// ZETA-MIGRATION-EXEMPT:` markers)**. Implementation begins with T-ICON-1 (Kiro spec) and T-ICON-2 (governance tests sized to current state). NIR product priorities (T1-8 / T1-10 / T0-A) are paused for the duration of this UI migration window per user direction.
**Author**: Kiro
**Related**: `docs/current tasks/2026-05-24-shadcn-to-zeta-flutter-migration.md` (T-UI, complete), `docs/current tasks/2026-05-24-tech-debt-cleanup-material-deprecated.md` (T-DEBT, partial), `.kiro/specs/full-zeta-migration/`, `.kiro/specs/material-to-zeta-button-sweep/`, `.kiro/specs/material-to-zeta-icons-sweep/` (this work)

## Decision log

| Date | Decision | Decided by |
|---|---|---|
| 2026-05-26 | Tier B curated mapping approach approved | User |
| 2026-05-26 | Tier C strategy = **C1 only** (keep Material with `// ZETA-MIGRATION-EXEMPT:` markers; no custom font in this round) | User |
| 2026-05-26 | T-ICON moved to front of priority list — supersedes T1-8 / T1-10 / T0-A queue position for the current UI migration window | User |

---

## 1. Why this scope exists

After T-UI-9 the Zeta theme, button widgets, and component primitives are wired suite-wide. **Iconography was never migrated.** Across the six Flutter packages there are 631 raw `Icons.*` references on 112 files using 263 distinct Material icon names. None of the prior Zeta specs (`full-zeta-migration` requirements 1–7, the button sweep, T-UI-1..9, or T-DEBT 1–4) cover icons.

If "no direct Material coupling" is a real product goal, icons are the largest remaining surface. The complication is that **`zeta_icons` does not cover ~half of what NMTK uses today**, so this is not a mechanical sweep. This document defines the scope, options, and effort honestly so the work can be queued correctly.

### Non-goals

- Not part of this scope: golden / visual regression tests (none exist suite-wide); colour audit (already T-DEBT R4); button widget swaps (T-UI complete).
- Not on the active queue: this is **cosmetic UI work**. T1-8 (NIR-CNL editor round-trip), T1-10 (sentence picker NIR alignment), and T0-A (workspace file I/O) take precedence per `MASTER_TASK_ORDER.md` §Scope Rules.

---

## 2. Inventory

### 2.1 Per-package usage

| Package | `Icons.*` hits | Files | Notes |
|---|---:|---:|---|
| `neurocnl/frontend` | 316 | 52 | Largest surface; Studio/canvas/deploy panels |
| `nmtk/neuro_toolkit` | 84 | 11 | Launcher shell, settings, module picker |
| `Neurohub/frontend` | 64 | 12 | Asset library, login, project detail |
| `Neurosense/frontend` | 60 | 12 | Sensor recording, replay, encoding |
| `nmtk_ui_core` | 59 | 15 | **Public API surface** — icons exposed as model fields |
| `Neurobench/frontend` | 48 | 10 | Workbench, comparison, regression trends |
| **Total** | **631** | **112** | |

(Full top-files list available in §A.)

### 2.2 Most-used Material icons (top 10 by call count)

| Icon | Hits | Direct Zeta match? |
|---|---:|---|
| `warning_amber_rounded` | 26 | No (`warning` exists; no amber variant) |
| `error_outline` | 23 | Yes |
| `check_circle_outline` | 21 | Yes (`check_circle_outline`) |
| `hub_outlined` | 16 | **No** — Tier C |
| `cancel_outlined` | 14 | Yes (`cancel_outline`) |
| `arrow_back_rounded` | 13 | Yes (`arrow_back_round`) |
| `play_arrow` | 12 | **No direct** — only `play` (Tier B) |
| `refresh` | 11 | Yes |
| `refresh_rounded` | 10 | Yes |
| `check_circle` | 9 | Yes |

### 2.3 ZetaIcons API surface

`zeta_icons 1.9.3` is on disk and **already re-exported by `package:zeta_flutter/zeta_flutter.dart`** — no pubspec change is required to *use* it. `ZetaIcons` is an `abstract class` exposing 2,115 `static const IconData` fields (snake_case names, three font families: `zeta-icons` default = round, `zeta-icons-round`, `zeta-icons-sharp`).

Key naming-convention deltas vs Material:

| Material suffix | Zeta equivalent |
|---|---|
| `_outlined` | `_outline` |
| `_rounded` | (drop — Zeta default IS round) |
| `_amber` | (drop — colour comes from styling) |
| `_round` (in Zeta) | explicit round font; same as default |
| `_sharp` (in Zeta) | sharp variant |

### 2.4 Coverage gap (the critical finding)

After applying the normalisation rules above against the full ZetaIcons name list:

- **Distinct icons matched: 108 / 263 (41 %)**
- **Call sites matched: 335 / 656 (51 %)**
- **Unmatched: 112 distinct stem icons covering 303 / 656 call sites (~49 %)**

ZetaIcons is biased toward Zebra-product use cases (barcode scanners, RFID, video calls, retail/warehouse). It lacks many icons that NMTK relies on for scientific and developer UX:

| Material icon (stem) | Hits | Why it matters in NMTK |
|---|---:|---|
| `hub*` | 20 | Network/graph hub — used in `network_graph_view`, neurohub branding |
| `play_arrow*` | 20 | Run/simulate triggers across Studio, deploy, replay |
| `account_tree*` | 12 | Pipeline / tree visualisation |
| `code*` | 13 | CNL editor, Python view, IR JSON view |
| `bolt*` | 12 | Fast/inference indicators |
| `science_outlined` | 5 | Validation, sandbox, experiment surfaces |
| `inventory_2*` | 7 | Asset / artifact bundles in Neurohub |
| `insights*` | 7 | Analytics, results panels |
| `compare_arrows_outlined` | 6 | Comparison screens |
| `monitor_heart*`, `architecture*`, `extension`, `terminal`, `equalizer`, `functions`, `dashboard_customize`, `auto_awesome*`, `auto_fix_high`, `model_training_outlined`, `rocket_launch_outlined`, `precision_manufacturing*`, `widgets_outlined`, `developer_board*`, `dns*`, `api*` | varied | Common technical / scientific iconography |

The full unmatched list (112 stems) lives in this scope's appendix §B and must be reviewed before implementation.

### 2.5 Public-API impact in `nmtk_ui_core`

These files expose `IconData` constants as part of model output that downstream packages consume:

- `lib/models/shell_models.dart` — workflow status icons
- `lib/models/pynq_deployment_model.dart` — deployment phase icons
- `lib/models/akida_deployment_model.dart` — deployment phase icons
- `lib/widgets/pipeline_stepper.dart` — pipeline step icons
- `lib/widgets/desktop_scaffold.dart` — sidebar default icons (also referenced in dartdoc)

The exposed type stays `IconData` (Zeta and Material `IconData` are interchangeable). What changes is the *value*. A regression test must assert that every `IconData` returned by these models resolves to a glyph that has a font (i.e. is not `null` and has `fontFamily != null`).

---

## 3. Strategy: three-tier mapping

A single mechanical sweep is not viable because of §2.4. The work splits into three tiers.

### Tier A — Direct match (mechanical, ~108 icons / 335 hits)

Apply normalisation rules to the icon name and replace if the resulting `ZetaIcons.<name>` exists.

Normalisation rules (in order):

1. `_outlined` → `_outline`
2. Drop `_rounded`
3. Drop `_amber`
4. Try `_round` suffix as a final fallback for explicit-round preference

Example diffs:

```dart
// Before
Icon(Icons.error_outline)                  // → ZetaIcons.error_outline
Icon(Icons.cancel_outlined)                // → ZetaIcons.cancel_outline
Icon(Icons.refresh_rounded)                // → ZetaIcons.refresh  (or refresh_round)
Icon(Icons.warning_amber_rounded)          // → ZetaIcons.warning  (lose amber tint; colour via Theme)
```

This tier can be driven by a script (Dart fix-tool / sed) with per-file `dart analyze` validation.

### Tier B — Semantic equivalent (curated, ~43 icons / unknown hits)

Icons where Zeta has a different name for the same concept. Requires a curated mapping table reviewed by a code owner before sweep. Confirmed candidates from §2.4 probing:

| Material | ZetaIcons | Notes |
|---|---|---|
| `play_arrow`, `play_arrow_rounded`, `play_arrow_outlined` | `play` / `play_outline` | Lose the triangle "arrow" — visually similar |
| `pause_circle_outline`, `play_circle_outline`, `play_circle_fill` | `pause_circle` / `play_circle` | Drop `_fill` / `_outline` distinction or use sharp |
| `arrow_back_ios_new_rounded`, `arrow_forward_ios` | `arrow_back` / `arrow_forward` | Drop iOS chevron style |
| `more_vert` | `more_vertical` | Rename only |
| `keyboard_arrow_down` | `arrow_down` | Drop keyboard prefix |
| `arrow_drop_down` | `arrow_down` | Same |
| `circle_outlined`, `circle` | `radio_button_outlined` / `circle` | Verify visual match |
| `check` | `tick` (verify) | |
| `save_as_rounded` | `save` + visual delta acceptable | |
| `open_in_new`, `open_in_browser`, `open_in_new_rounded` | `open_in_new_window` | Rename only |
| `info_outline`, `info_outline_rounded` | `info` (`outline` font variant) | |
| `description`, `description_outlined` | `text_snippet` or `article` (verify) | |
| `delete_outline`, `delete_outline_rounded` | `delete` / `delete_outline` (Zeta has alt) | |

Each Tier B mapping needs a one-line designer/code-owner approval comment in the spec PR before the sweep runs.

### Tier C — No Zeta equivalent (~112 stems / 303 hits) — **C1 chosen**

**Decision (2026-05-26): C1.** Each retained `Icons.*` reference gets an inline `// ZETA-MIGRATION-EXEMPT: <reason>` marker. The governance test (see §4) counts markers and asserts `Icons.*` hits ≤ marker count. Outcome: `Icons.*` is still imported and `material.dart` is still a transitive dependency, but every retained call is tracked and any *new* unannotated `Icons.*` call fails CI.

**C2 (custom NMTK icon font) is deferred.** If "zero Material coupling" is required later, C2 can be picked up as a separate package-build task — see §C2 details below for reference.

#### C2 reference (deferred)

Build a new `nmtk_icons` asset under `nmtk_ui_core/assets/icons/` containing the missing glyphs:

1. Pull SVGs from Material Symbols (Apache 2.0) — license-clean.
2. Generate a single TrueType font via `fonttools` or FontForge (CI-reproducible).
3. Generate `lib/nmtk_icons.g.dart` with `static const IconData science = IconData(0xE001, fontFamily: 'NmtkIcons', fontPackage: 'nmtk_ui_core')` etc.
4. Register the font asset in `nmtk_ui_core/pubspec.yaml`.
5. Re-export from the barrel.
6. Import everywhere alongside `ZetaIcons`.

---

## 4. Governance & test gates

### 4.1 Per-package governance test

Create `test/governance/material_icons_audit_test.dart` in each of the six packages, modelled on the existing `neurocnl/frontend/test/governance/zeta_first_audit_test.dart`. The test:

- Scans every `.dart` file under `lib/`.
- Counts active (non-comment) lines containing the token `Icons.`.
- Counts marker comments matching the regex `ZETA-MIGRATION-EXEMPT:\s*[^\n]+`.
- Asserts `icons_hits <= marker_count`.

```dart
// Example marker (Tier C1 exemption)
Icon(
  Icons.science_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (scientific flask)
  color: tokens.metadataForeground,
)
```

After C2 lands, the marker allowance drops to zero and the test asserts `icons_hits == 0`.

### 4.2 Per-file gate

`dart analyze <path>` must report zero new errors after each file is modified — same convention as T-DEBT and the button sweep.

### 4.3 Per-package gate

`flutter test <package>/` must remain at the pre-existing baseline failure count after each package sweep completes.

### 4.4 nmtk_ui_core model regression

Add `nmtk_ui_core/test/models/deployment_icon_resolution_test.dart` (and equivalents for `shell_models`) asserting:

- Every `IconData` returned by `PynqDeploymentPhase.icon` / `AkidaDeploymentPhase.icon` / `WorkflowStep.icon` is non-null.
- `iconData.fontFamily` matches `'zeta-icons*'` (Tier A/B) or `'NmtkIcons'` (Tier C2 only).

### 4.5 Final cross-package grep

Same convention as the button sweep:

```bash
grep -rE '\bIcons\.' --include='*.dart' \
  nmtk_ui_core/lib \
  neurocnl/frontend/lib \
  Neurohub/frontend/lib \
  Neurobench/frontend/lib \
  Neurosense/frontend/lib \
  nmtk/neuro_toolkit/lib | grep -v 'ZETA-MIGRATION-EXEMPT'
```

Must return zero hits at C2 completion (or only annotated hits at C1 completion).

### 4.6 Out of scope (called out explicitly)

- **Visual / golden regression**: no golden test suite exists suite-wide. Migrating icons can shift glyph shapes (especially Tier B). Risk is accepted; mitigation is manual smoke pass of the four highest-traffic screens (Studio, deploy, asset library, workbench) per package.

---

## 5. Phased plan

Six tasks, tracked under provisional ID **T-ICON**. Recommended ordering — each phase is a separate PR.

### T-ICON-1 — Spec PR (no code changes)

- Land this scope doc.
- Land `.kiro/specs/material-to-zeta-icons-sweep/{requirements,design,tasks}.md` modelled on the button sweep.
- Land the curated Tier B mapping table (CSV in spec).
- Land the Tier C strategy decision (C1 vs C2 vs C1→C2).
- **Effort: 0.5 day.**

### T-ICON-2 — Add governance tests with allowlist sized to current state

- Add the six `material_icons_audit_test.dart` files; size each marker allowlist to the current `Icons.*` count so the test passes immediately and prevents *new* regressions while the sweep runs.
- Add the `nmtk_ui_core` model regression test (initially relaxed: just non-null).
- **Effort: 0.5 day.**

### T-ICON-3 — Tier A mechanical sweep

- Apply Tier A normalisation across all six packages.
- Files in descending hit-count order (mirrors the button sweep convention).
- After each file: `dart analyze`. After each package: `flutter test`.
- Reduce each governance test's marker allowlist as call sites are converted.
- **Effort: 2–3 days.** ~108 distinct icons / 335 call sites; mostly script-driven.

### T-ICON-4 — Tier B curated sweep

- Apply Tier B mapping table per the approved CSV.
- Same per-file / per-package gates.
- **Effort: 1–2 days.** Manual review per call site for visual acceptability.

### T-ICON-5 — Tier C strategy execution

- **If C1**: annotate every remaining `Icons.*` reference with `// ZETA-MIGRATION-EXEMPT: <reason>`. Lock the governance allowlist at the final count.
  - **Effort: 1 day.**
- **If C2**: build the `nmtk_icons` font and generated Dart, replace the remaining 303 call sites with `NmtkIcons.*`.
  - **Effort: 3–5 days** (font pipeline + sweep + license review).

### T-ICON-6 — Final verification

- Cross-package grep returns zero unannotated hits (C1) or zero hits total (C2).
- Manual smoke pass of the four high-traffic screens per package.
- Update `MASTER_TASK_ORDER.md` to mark T-ICON complete.
- **Effort: 0.5 day.**

### Effort summary

| Phase | C1 path | C1→C2 path |
|---|---:|---:|
| T-ICON-1 spec | 0.5 d | 0.5 d |
| T-ICON-2 governance | 0.5 d | 0.5 d |
| T-ICON-3 Tier A | 2–3 d | 2–3 d |
| T-ICON-4 Tier B | 1–2 d | 1–2 d |
| T-ICON-5 Tier C | 1 d (C1) | 4–6 d (C1 + C2) |
| T-ICON-6 verify | 0.5 d | 0.5 d |
| **Total** | **5.5–7.5 days** | **8.5–12.5 days** |

---

## 6. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Tier B visual drift confuses users (e.g. `play_arrow` → `play` is a different glyph shape) | High | Medium | Designer sign-off on every Tier B mapping; manual smoke pass per package |
| Loss of `warning_amber` colour cue degrades affordance | High | Low | Apply `tokens.warningColor` to the `Icon(...).color` prop alongside the icon swap |
| `nmtk_ui_core` model API consumers (downstream of an unreleased version) get different `IconData` after sweep | Medium | Low | Keep the type `IconData`; only the constant value changes; covered by §4.4 regression test |
| Tier C2 font pipeline becomes a maintenance burden | Medium | Medium | Use `fonttools` reproducibly in CI; document the regen command in `nmtk_ui_core/README.md` |
| Material icon Apache 2.0 redistribution requires NOTICE file in app bundles | Low | Low | Bundle NOTICE in `nmtk_ui_core/LICENSE` and propagate via pub-published metadata |
| ZetaIcons 1.9.3 default font (`zeta-icons` = round) doesn't match Material's default outline appearance everywhere | Medium | Low | Default to `_outline` Zeta variants for Material `Icons.foo` (no suffix); use round only when Material `_rounded` was specified |
| Sweep breaks code that pattern-matches on `IconData` (e.g. `if (icon == Icons.X) ...`) | Low | High | Grep for `== Icons\.` before sweep; refactor to compare on a tagged enum if found |
| Active priorities (T1-8 / T1-10 / T0-A) get blocked or delayed by this work | High if started now | High | Queue T-ICON behind active priorities per `MASTER_TASK_ORDER.md` §Scope Rules; do not pull forward |

---

## 7. Execution status

**As of 2026-05-26 the work is active.** T-ICON-1 (this scope + Kiro spec) and T-ICON-2 (governance tests sized to current state) are the immediate first PR. Tier A sweep follows. Tier B curated mapping table is approved in approach; individual rows are reviewed during T-ICON-4 with the design CSV in `.kiro/specs/material-to-zeta-icons-sweep/design.md`. Tier C strategy is **C1 only** — every retained `Icons.*` gets an exemption marker, and the governance test ratchets the baseline downward as the sweep progresses.

NIR product priorities (T1-8 / T1-10 / T0-A) are paused for the duration of this UI migration window per user direction. They resume after T-ICON-6 lands.

---

## Appendix A — Per-file hit hotspots (top 10)

```
38  nmtk/neuro_toolkit/lib/widgets/module_picker_panel.dart
27  nmtk_ui_core/lib/widgets/desktop_scaffold.dart
27  Neurobench/frontend/lib/screens/workbench_shell.dart
22  neurocnl/frontend/lib/widgets/simulator_panel.dart
21  neurocnl/frontend/lib/widgets/export_menu.dart
18  Neurosense/frontend/lib/app.dart
18  neurocnl/frontend/lib/screens/studio/compiled_artifacts/compiled_artifacts_panel.dart
18  neurocnl/frontend/lib/widgets/cnl_sentence_builder_dialog.dart
17  neurocnl/frontend/lib/screens/analysis_screen.dart
17  neurocnl/frontend/lib/screens/server_setup_screen.dart
```

## Appendix B — Tier C unmatched stems (112 distinct)

```
account_tree, add_link, alt_route, api, architecture, arrow_back_ios_new,
arrow_drop_down, arrow_forward_ios, article, attach_file, auto_awesome,
auto_awesome_mosaic, auto_fix_high, auto_graph, balance, bar_chart, blur_on,
bolt, bug_report, cable, check, circle, code, code_off, compare_arrows,
compress, copy, dashboard_customize, data_usage, description,
developer_board, dns, do_not_disturb_alt, door_front_door,
download_for_offline, drive_file_rename, edit_note, equalizer, explore,
extension, fact_check, fiber_manual_record, file_open, filter_alt_off,
filter_none, folder_copy, folder_open, functions, graphic_eq, handyman,
hardware, hourglass_top, hub, info, info_outline, input, insert_drive_file,
insights, inventory_2, keyboard_arrow_down, keyboard_tab, language,
lightbulb, linear_scale, link_off, local_fire_department, menu, menu_open,
model_training, monitor_heart, more_vert, multiline_chart, notes,
open_in_browser, open_in_new, output, panorama_horizontal, pause_circle,
pause_circle_outline, play_arrow, play_circle, play_circle_fill,
play_circle_outline, precision_manufacturing, replay_circle_filled,
rocket_launch, route, rule_folder, save_as, science, search_off, sensors,
settings_input_component, settings_input_composite, shield, show_chart,
speed, square, sticky_note_2, storage, stream, sync_problem, system_update,
terminal, text_snippet, usb_off, video_library, videocam_off, view_stream,
web, widgets, wifi_find
```
