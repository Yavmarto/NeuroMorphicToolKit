# CEL-167 — Remove bottom toast messages

**Status:** done

## Summary
Rewired `NmtkSnackBars` / `NmtkToasts` to push `NmtkNotificationCenter` top-right banners. Removed remaining `ScaffoldMessenger` / `SnackBar` call sites across `nmtk/neuro_toolkit/lib`, including hosted-feature error fallback in `cross_module_navigation.dart`.

## Key files
- `nmtk/neuro_toolkit/lib/ui_core/widgets/snack_bars.dart`
- `nmtk/neuro_toolkit/lib/ui_core/widgets/toasts.dart`
- `nmtk/neuro_toolkit/lib/ui_core/widgets/notification_center.dart` (`onDismissed`)
- `nmtk/neuro_toolkit/lib/screens/tool_view/cross_module_navigation.dart`

## Verify
```bash
cd nmtk/neuro_toolkit
rg 'ScaffoldMessenger|showSnackBar|SnackBar\(' lib/   # should be clean
flutter test test/ui_core/snack_bars_test.dart test/report_hosted_feature_error_test.dart test/features/neurocnl/widgets/export_menu_test.dart
```
