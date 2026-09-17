import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class ResultsPlatformTab extends StatelessWidget {
  const ResultsPlatformTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
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
          color: selected
              ? colors.mainPrimary.withValues(alpha: 0.1)
              : colors.surfaceHover,
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusChip,
          ),
          border: Border.all(
            color: selected ? colors.mainPrimary : colors.borderDefault,
          ),
        ),
        child: Text(
          label,
          style: Zeta.of(context).textStyles.labelSmall.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? colors.mainPrimary : null,
          ),
        ),
      ),
    );
  }
}
