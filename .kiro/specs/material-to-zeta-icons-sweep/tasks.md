# Implementation Plan — material-to-zeta-icons-sweep

## Overview

Three-tier sweep replacing Material `Icons.*` with `ZetaIcons.*` (Tier A direct + Tier B curated) and annotating residuals with `// ZETA-MIGRATION-EXEMPT:` markers (Tier C1). Six packages, 631 hits, 112 files, 263 distinct icon names.

## Task Dependency Graph

```json
{
  "waves": [
    { "wave": 1, "tasks": [1, 2] },
    { "wave": 2, "tasks": [3] },
    { "wave": 3, "tasks": [4] },
    { "wave": 4, "tasks": [5] },
    { "wave": 5, "tasks": [6] },
    { "wave": 6, "tasks": [7] }
  ]
}
```

Tasks 1 and 2 can run in parallel. Tasks 3–7 are sequential.

## Tasks

- [ ] 1. **T-ICON-1 — Spec PR** (this PR)
  - Land `requirements.md`, `design.md`, `tasks.md` under `.kiro/specs/material-to-zeta-icons-sweep/`.
  - Land scope doc `docs/current tasks/2026-05-26-material-icons-to-zeta-icons-migration.md`.
  - Update `docs/current tasks/MASTER_TASK_ORDER.md` to add T-ICON section at the front of the active queue.
  - Demo: spec files exist; `MASTER_TASK_ORDER.md` mentions T-ICON.

- [ ] 2. **T-ICON-2 — Governance tests with current-state baseline**
  - Add `test/governance/material_icons_audit_test.dart` to all six packages.
  - Set `kIconsBaseline` to the current `Icons.` hit count per package (`neurocnl/frontend`: 316, `nmtk/neuro_toolkit`: 84, `Neurohub/frontend`: 64, `Neurosense/frontend`: 60, `nmtk_ui_core`: 59, `Neurobench/frontend`: 48).
  - Add `nmtk_ui_core/test/models/icon_resolution_test.dart` asserting non-null `IconData` and non-null `fontFamily` for every model-exposed icon.
  - Run `flutter test test/governance/material_icons_audit_test.dart` in each package — must pass.
  - Demo: governance test passes in all six packages with the documented baseline.

- [ ] 3. **T-ICON-3 — Tier A mechanical sweep**
  - For each package in descending hit-count order (neurocnl, nmtk, Neurohub, Neurosense, nmtk_ui_core, Neurobench), apply the Tier A normalisation rules (`design.md §Tier A`) and replace matching `Icons.X` with `ZetaIcons.<normalised>`.
  - After each file: `dart analyze <file>` returns zero new errors.
  - After each package: `flutter test <package>/` at baseline failure count.
  - After each package: decrement `kIconsBaseline` in the package's governance test to the new hit count.
  - Demo: governance test passes; Tier A coverage (~335 / 656 call sites converted).

- [ ] 4. **T-ICON-4 — Tier B curated sweep**
  - Apply the Tier B mapping table (`design.md §Tier B`) uniformly across all six packages.
  - Where a row in the table proves visually unacceptable on review, drop the row and route the icon to Tier C1 instead (annotate with `ZETA-MIGRATION-EXEMPT: Tier B candidate rejected — <reason>`).
  - Add new Tier B candidates discovered during sweep to the `design.md` table before applying.
  - Per-file `dart analyze`. Per-package `flutter test`. Decrement baselines.
  - Demo: Tier B icons converted; governance test passes.

- [ ] 5. **T-ICON-5 — Tier C1 annotation pass**
  - For every remaining `Icons.X` reference in `lib/`, add `// ZETA-MIGRATION-EXEMPT: <reason>` either trailing or on the line immediately preceding.
  - Set each package's `kIconsBaseline` to `0` (residuals are now covered by markers, not the baseline ratchet).
  - The governance test now asserts `icons_hits == marker_count`.
  - Demo: every `Icons.*` reference outside `test/` has an exemption marker.

- [ ] 6. **T-ICON-6 — Final cross-package verification**
  - Run final verification grep from `design.md §Final verification` — zero unannotated hits.
  - Run `flutter test` across all six packages — all at baseline failure count.
  - Run `flutter analyze` across all six packages — zero new errors.
  - Manual smoke pass of high-traffic screens per package: Studio (neurocnl), launcher home + module picker (nmtk), asset library (Neurohub), workbench shell (Neurobench), live signal viewer (Neurosense), desktop scaffold (nmtk_ui_core).
  - Update `MASTER_TASK_ORDER.md` to mark T-ICON complete and resume NIR product priorities (T1-8 / T1-10 / T0-A).
  - Demo: zero unannotated `Icons.*` hits across all six packages.

- [ ] 7. **(Future, deferred) T-ICON-7 — Tier C2 custom NMTK icon font**
  - Not in scope for this round. Track separately if zero-Material is later required. See scope doc `§3 Tier C2 reference`.

## Notes

- REQ-1.4: Tier A is allowed to drop `_amber` colour suffixes; the missing colour cue is reapplied via `Icon(...).color = tokens.warningColor` at the call site.
- REQ-2.4: visual deltas in Tier B are accepted without golden-test coverage. Manual smoke pass in T-ICON-6 is the only visual gate.
- REQ-6: do not change the *type* of public-API model icon fields — `IconData` is the contract; only constants change.
- REQ-8.3: do NOT modify `test/**/*.dart`. Test files may legitimately reference Material widgets.
- The governance test (T-ICON-2) excludes `test/` from its own scan; only `lib/` is policed.
