import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Toggles between per-platform and combined workflow results.

class CompareToggleChip extends StatelessWidget {
  const CompareToggleChip({
    super.key,
    required this.compareMode,
    required this.onTap,
  });

  final bool compareMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: compareMode
              ? colors.mainSecondary.withValues(alpha: 0.15)
              : colors.surfaceHover,
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusChip,
          ),
          border: Border.all(
            color: compareMode ? colors.mainSecondary : colors.borderDefault,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              compareMode ? ZetaIcons.close : ZetaIcons.analytics,
              size: 14,
              color: compareMode ? colors.mainSecondary : null,
            ),
            const SizedBox(width: 4),
            Text(
              compareMode ? 'Per Platform' : 'Compare All',
              style: TextStyle(
                fontSize: 12,
                fontWeight: compareMode ? FontWeight.w600 : FontWeight.normal,
                color: compareMode ? colors.mainSecondary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
