# Align mobile Step 1 (Setup) with desktop ground truth

## Problem
The neurocnl Studio's Step 1 ("Setup", `SnnWorkflowPhase.selectData`) is one widget (`_SetupStep` in `setup_step.dart`) that internally branches into a desktop layout and a mobile layout (`<840px`), and the two had drifted apart: mobile showed a mobile-only "Open Server Setup" error escape hatch desktop never had, mobile's plain leading icons lacked the Zeta color token desktop's buttons resolve to, and mobile mislabeled/misgrouped sections relative to desktop (`Frameworks`/`Data` vs desktop's `Target platform`/`Dataset`, and `Benchmark` nested under `Workspace` instead of its own section).

## Fix
- `neurocnl/frontend/lib/screens/studio/steps/setup_step.dart`: deleted the mobile-only `catalogAsync.hasError` branch (Retry/"Open Server Setup"/Skip) and the now-dead `_DatasetLoadErrorPanel` widget, so mobile behaves like desktop (no special-cased dataset-fetch-failure UI); gave mobile its own `Benchmark (optional)` section, renamed `Frameworks`→`Target platform` (dialog title `Select Frameworks`→`Select targets`) and `Data`→`Dataset` to match desktop's section names; added `color: Zeta.of(context).colors.mainDefault` to the mobile leading action icons (`upload_file` ×2, `cloud_download`, `download`) to match the token desktop's `NmtkOutlinedButton` icons resolve to via Zeta's button style.
- `neurocnl/frontend/lib/screens/studio_screen.dart`: removed the now-unused `server_config_provider.dart` and `backend_issue_formatter.dart` imports.
- `neurocnl/frontend/test/screens/studio_responsive_audit_test.dart`: updated stale "Frameworks summary" comment/test name to "Target platform summary" (assertion itself, `find.text('1 selected')`, was unaffected).

## Verification
- `flutter analyze` on the three touched files: clean except 4 pre-existing `unused_element` warnings in `studio_screen.dart` (confirmed present on the unstashed baseline, unrelated to this change).
- `flutter test test/screens/studio_responsive_audit_test.dart`: all 6 pass. `flutter test test/screens/setup_step_local_import_test.dart test/screens/studio_screen_test.dart`: 13 pass / 21 fail, and the failing-test list is byte-identical against a stashed pre-change baseline (pre-existing "Timer is still pending" issue, unrelated). `dart format` applied.
