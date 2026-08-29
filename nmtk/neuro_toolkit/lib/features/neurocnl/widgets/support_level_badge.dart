import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart' show ZetaIcons, NmtkShellTokens;

/// A compact pill-shaped badge for a nir_support.py classification level
/// ('exact' / 'approximate' / 'unsupported' / null-while-loading).
///
/// Visually modeled on simulator_panel.dart's private _PreflightBadge (same
/// color/icon mapping), but a fresh public widget rather than an extraction
/// from that file, since it is heavily tested and unrelated to this surface.
class SupportLevelBadge extends StatelessWidget {
  const SupportLevelBadge({super.key, required this.level});

  /// One of 'exact', 'approximate', 'unsupported', or null.
  final String? level;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final (label, color, icon) = switch (level) {
      'exact' => (
        'Fully supported',
        tokens.healthyColor,
        ZetaIcons.check_circle_outline,
      ),
      'approximate' => (
        'Approximate',
        tokens.warningColor,
        ZetaIcons.warning_outline,
      ),
      'unsupported' => (
        'Unsupported',
        tokens.errorColor,
        ZetaIcons.cancel_outline,
      ),
      _ => ('Unknown', tokens.warningColor, ZetaIcons.warning_outline),
    };

    final theme = Theme.of(context);
    const chipRadius = 999.0;
    final bg = color.withValues(alpha: 0.12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
