import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Workspace tab styling shared by Studio's workspace chrome.
class ZetaStyledTab extends StatelessWidget {
  const ZetaStyledTab({
    super.key,
    required this.label,
    required this.isActive,
    this.onTap,
    this.isHeader = false,
    this.trailing,
  });

  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  /// When `true`, render with a slightly muted look used for the
  /// non-tappable workspace-name pill that prefixes multi-file tab lists.
  final bool isHeader;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final activeColor = colors.mainPrimary;
    final inactiveColor = isHeader ? colors.mainDefault : colors.mainSubtle;
    final foreground = isActive ? activeColor : inactiveColor;
    final indicatorColor = isActive ? activeColor : Colors.transparent;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );

    final tab = DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: indicatorColor, width: 2)),
      ),
      child: content,
    );

    if (onTap == null) {
      return tab;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
      child: tab,
    );
  }
}
