# Implementation Plan: material-to-zeta-button-sweep

## Overview

Mechanical find-and-replace sweep replacing ElevatedButton, TextButton, and OutlinedButton with ZetaButton equivalents across 5 Flutter frontend packages (104 hits, 45 files).

## Task Dependency Graph

```json
{
  "waves": [
    { "wave": 1, "tasks": [5] },
    { "wave": 2, "tasks": [6] },
    { "wave": 3, "tasks": [7] },
    { "wave": 4, "tasks": [8] }
  ]
}
```

Tasks are sequential: each package sweep proceeds after the previous completes.

## Tasks

- [x] 5. Replace Material buttons in `neurocnl/frontend` (52 hits, 18 files)
  - Read each file before editing. Work through files in the order listed in design.md §Task 5.
  - Apply the replacement map from design.md for every `ElevatedButton`, `TextButton`, `OutlinedButton` instance.
  - For loading-state buttons (conditional `CircularProgressIndicator` icon), apply the loading state pattern from design.md.
  - After each file: run `dart analyze neurocnl/frontend/lib/<path>` — must be zero errors.
  - After all 18 files: run `flutter test neurocnl/frontend/` — must be at baseline failure count.
  - Demo: `grep -r 'ElevatedButton\b\|TextButton\b\|OutlinedButton\b' neurocnl/frontend/lib --include='*.dart'` returns zero hits.

- [x] 6. Replace Material buttons in `Neurohub/frontend` (20 hits, 11 files)
  - Work through files in the order listed in design.md §Task 6.
  - After each file: `dart analyze Neurohub/frontend/lib/<path>` — zero errors.
  - After all 11 files: `flutter test Neurohub/frontend/` — baseline failure count.
  - Demo: zero grep hits in `Neurohub/frontend/lib`.

- [x] 7. Replace Material buttons in `Neurobench/frontend` (14 hits) and `Neurosense/frontend` (5 hits)
  - Work Neurobench files first, then Neurosense files, in the order listed in design.md §Task 7.
  - After Neurobench files: `flutter test Neurobench/frontend/` — baseline.
  - After Neurosense files: `flutter test Neurosense/frontend/` — baseline.
  - Demo: zero grep hits in both `lib/` dirs.

- [x] 8. Replace Material buttons in `nmtk/neuro_toolkit` (13 hits, 8 files) + final sweep
  - Work files in the order listed in design.md §Task 8.
  - After all 8 files: `flutter test nmtk/neuro_toolkit/` — baseline.
  - Run the final verification grep from design.md §Final Verification — must return zero hits.
  - Run `flutter test` across all 5 packages — all at baseline.
  - Demo: grep clean across all 5 `lib/` dirs; all test suites at baseline failure counts.

## Notes

- REQ-3: Each modified file must import `zeta_flutter` or `nmtk_ui_core` — no undefined-name compile errors.
- REQ-4.3: Do not touch existing `NmtkOutlinedButton`, `NmtkPrimaryButton`, or `ZetaButton` usages.
- REQ-5: Test files are NOT modified.
- See design.md §Loading State Pattern for buttons with conditional CircularProgressIndicator icons.
