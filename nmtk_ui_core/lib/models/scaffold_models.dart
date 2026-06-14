import 'package:flutter/material.dart';

/// A single navigation destination in the NMTK rail/bottom bar.
class NmtkSidebarItem {
  const NmtkSidebarItem({
    required this.id,
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.badgeCount,
  });

  /// Stable string id used for selection tracking and accessibility labels.
  final String id;

  /// Human-readable label shown in tooltip when collapsed.
  final String label;

  final IconData icon;

  /// Icon shown in place of [icon] when this item is selected.
  final IconData? selectedIcon;

  /// When non-null and > 0, a badge with this number is shown.
  final int? badgeCount;
}

/// One entry in the [NmtkUserProfile] dropdown/bottom sheet.
class NmtkUserProfileAction {
  const NmtkUserProfileAction({
    required String this.label,
    this.icon,
    this.onPressed,
    this.isDestructive = false,
  }) : isDivider = false;

  /// Creates a visual divider row.
  const NmtkUserProfileAction.divider()
    : label = null,
      icon = null,
      onPressed = null,
      isDestructive = false,
      isDivider = true;

  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isDestructive;
  final bool isDivider;
}

/// User identity shown in the scaffold profile chip.
class NmtkUserProfile {
  const NmtkUserProfile({
    required this.displayName,
    this.email,
    this.avatarUrl,
    this.avatarFallback,
    this.actions = const [],
  });

  final String displayName;
  final String? email;
  final String? avatarUrl;
  final String? avatarFallback;
  final List<NmtkUserProfileAction> actions;
}

/// Abstract interface for New/Open/Save/Save-As file operations.
abstract class NmtkFileActionDelegate {
  void onNewFile();
  void onOpenFile();
  void onSaveFile();
  void onSaveFileAs();
}
