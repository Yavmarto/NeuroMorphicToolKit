import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/hardware_target/hardware_target_dialog/saved_hardware_target_entry.dart';

class HardwareTargetDialogData {
  const HardwareTargetDialogData({
    required this.targetType,
    required this.entries,
    this.loadErrorMessage,
  });

  final String targetType;
  final List<SavedHardwareTargetEntry> entries;

  /// When non-null, the dialog shows a warning banner with this message
  /// instead of silently failing to open (e.g. launcher service is down).
  final String? loadErrorMessage;
}
