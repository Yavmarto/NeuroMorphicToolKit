import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';

class NmtkInfoChip extends StatelessWidget {
  const NmtkInfoChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    ZetaColors? colors;
    try {
      colors = Zeta.of(context).colors;
    } catch (_) {}

    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);

    final bg = colors != null
        ? colors.surfacePrimarySubtle
        : tokens.runningColor.withValues(alpha: 0.08);

    final border = colors != null
        ? colors.borderPrimary
        : tokens.runningColor.withValues(alpha: 0.35);

    final iconColor = colors != null
        ? colors.mainPrimary
        : theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radiusChip),
        color: bg,
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Text(
            '$label: $value',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
