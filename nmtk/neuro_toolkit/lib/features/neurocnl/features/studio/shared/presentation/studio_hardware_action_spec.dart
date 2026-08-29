import 'package:flutter/widgets.dart';

/// Describes a hardware-workflow action rendered by [StudioHardwareActionWrap].

enum StudioHardwareActionVariant { filled, outlined }

class StudioHardwareActionSpec {
  const StudioHardwareActionSpec({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.variant = StudioHardwareActionVariant.filled,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final StudioHardwareActionVariant variant;
}
