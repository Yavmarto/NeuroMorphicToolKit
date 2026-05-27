# Requirements Document — material-to-zeta-icons-sweep

## Introduction

After T-UI-9 the suite uses `zeta_flutter ^1.4.5` for theme and component widgets, but iconography was never migrated. There are 631 raw `Icons.*` references in 112 files across six Flutter packages using 263 distinct Material icon names. None of the prior Zeta specs cover icons.

`zeta_icons 1.9.3` (already re-exported via `package:zeta_flutter/zeta_flutter.dart`) provides 2,115 `IconData` constants but covers only ~51 % of NMTK's call sites — ZetaIcons is biased toward Zebra-product use cases (barcode scanners, RFID, retail) and lacks many scientific/developer icons NMTK relies on (`hub`, `science`, `account_tree`, `bolt`, `code`, `inventory_2`, `insights`, `compare_arrows`, etc.).

This spec defines a three-tier sweep: **Tier A** mechanical normalisation, **Tier B** curated semantic mapping, **Tier C1** documented exemption for icons with no Zeta equivalent. Tier C2 (custom NMTK icon font) is explicitly deferred.

Full background, inventory, and rationale: `docs/current tasks/2026-05-26-material-icons-to-zeta-icons-migration.md`.

## Scope

Six packages, 631 hits, 112 files, 263 distinct icon names:

| Package | Hits | Files |
|---|---:|---:|
| `neurocnl/frontend` | 316 | 52 |
| `nmtk/neuro_toolkit` | 84 | 11 |
| `Neurohub/frontend` | 64 | 12 |
| `Neurosense/frontend` | 60 | 12 |
| `nmtk_ui_core` | 59 | 15 |
| `Neurobench/frontend` | 48 | 10 |

## Glossary

- **Tier A**: Material icons that map directly to ZetaIcons after applying the four normalisation rules (`_outlined`→`_outline`, drop `_rounded`, drop `_amber`, try `_round` suffix).
- **Tier B**: Material icons with no direct match but a clear semantic equivalent in ZetaIcons (curated mapping table in `design.md`).
- **Tier C1**: Material icons with no Zeta equivalent. Retained as `Icons.*` with a mandatory `// ZETA-MIGRATION-EXEMPT: <reason>` marker.
- **Marker**: Inline comment matching the regex `ZETA-MIGRATION-EXEMPT:\s*[^\n]+` on the same line as a retained `Icons.*` reference, or on the immediately preceding line.
- **Affected packages**: The six packages listed in §Scope.

## Requirements

### REQ-1: Tier A normalisation

1.1 Every `Icons.X` reference where `X` matches a ZetaIcons name after applying the normalisation rules MUST be replaced with the corresponding `ZetaIcons.<normalised>` reference.

1.2 The normalisation rules MUST be applied in this order: (a) replace trailing `_outlined` with `_outline`; (b) drop trailing `_rounded`; (c) drop infix `_amber`; (d) if no match yet, try appending `_round` to the result of (a)–(c).

1.3 If after normalisation the resulting name does not exist in `ZetaIcons`, the icon falls through to Tier B or Tier C1.

1.4 Lossy normalisations MUST be acceptable when no information is encoded: `Icons.warning_amber_rounded` → `ZetaIcons.warning` is acceptable because amber is a colour cue, applied separately via `Icon(...).color = tokens.warningColor`.

### REQ-2: Tier B curated mapping

2.1 The Tier B mapping table in `design.md` lists Material → Zeta semantic substitutions (e.g. `play_arrow` → `play`, `more_vert` → `more_vertical`, `arrow_drop_down` → `arrow_down`).

2.2 Each Tier B substitution MUST be applied uniformly across all six packages.

2.3 New Tier B rows discovered during the sweep MUST be added to the table in `design.md` before the substitution lands.

2.4 Tier B substitutions that change visible glyph shape (e.g. `play_arrow` triangle → `play` triangle-with-circle) are accepted as cosmetic deltas; visual-regression coverage is out of scope.

### REQ-3: Tier C1 exemption

3.1 Every Material icon with no direct Tier A match and no curated Tier B substitution MUST be retained as `Icons.X` with an inline marker comment.

3.2 The marker MUST match the regex `ZETA-MIGRATION-EXEMPT:\s*[^\n]+` and MUST appear on the same line as the `Icons.` reference or on the line immediately preceding it.

3.3 The marker text after `ZETA-MIGRATION-EXEMPT:` MUST briefly explain why no Zeta equivalent exists (e.g. `no Zeta equivalent (graph hub icon)`).

3.4 No Tier C2 (custom NMTK icon font) work is in scope.

### REQ-4: Governance test (per package)

4.1 Each of the six packages MUST contain `test/governance/material_icons_audit_test.dart`.

4.2 The test MUST scan every `.dart` file under `lib/` and count active (non-comment) lines containing the token `Icons.`.

4.3 The test MUST count comment markers matching the regex `ZETA-MIGRATION-EXEMPT:\s*[^\n]+` (file-wide, not just preceding lines).

4.4 The test MUST assert `icons_hits ≤ marker_count + baseline`, where `baseline` is a `const int` declared at the top of the test file representing the current grandfathered count.

4.5 At T-ICON-2 introduction the `baseline` MUST equal the current `Icons.` hit count for that package, so the test passes immediately. The `baseline` MUST decrease monotonically as the sweep progresses; once the sweep is complete the `baseline` MUST equal `0` and the test reduces to `icons_hits == marker_count`.

4.6 Test files in the package's own `test/` directory MUST be excluded from the scan (test fixtures may legitimately reference Material widgets to verify migration-related governance).

### REQ-5: Per-file and per-package gates

5.1 After each file is modified during the sweep, `dart analyze <path>` MUST return zero new errors.

5.2 After each package is fully swept, `flutter test <package>/` MUST pass at the pre-existing baseline failure count.

5.3 The governance test added in REQ-4 MUST pass after each commit.

### REQ-6: Public API stability

6.1 Files in `nmtk_ui_core/lib/models/` and `nmtk_ui_core/lib/widgets/` that expose `IconData` constants as part of public API (`shell_models.dart`, `pynq_deployment_model.dart`, `akida_deployment_model.dart`, `pipeline_stepper.dart`) MUST keep the exposed type as `IconData`. Only the constant value changes.

6.2 A regression test MUST assert that every `IconData` returned by these models is non-null and that its `fontFamily` is non-null.

### REQ-7: Final cross-package verification

7.1 After all per-package sweeps are complete, the cross-package grep `grep -rE '\bIcons\.' --include='*.dart' lib/ | grep -v 'ZETA-MIGRATION-EXEMPT'` across all six `lib/` directories MUST return zero unannotated hits.

7.2 The six governance tests MUST all pass with `baseline = 0`.

### REQ-8: Out of scope

8.1 Visual / golden regression tests are NOT introduced by this spec.

8.2 Custom NMTK icon font (Tier C2) is NOT built in this spec.

8.3 Test files (`test/**/*.dart`) are NOT modified.

8.4 Material `IconData` references that are part of Flutter framework API surface (e.g. `BottomNavigationBar` icon parameters) are not in scope unless the call site is in `lib/`.
