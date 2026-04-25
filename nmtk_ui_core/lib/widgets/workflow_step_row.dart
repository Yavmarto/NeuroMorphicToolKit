import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/widgets/tone.dart';

class NmtkWorkflowStepRow extends StatelessWidget {
  const NmtkWorkflowStepRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.tone,
    required this.icon,
    this.padding = const EdgeInsets.only(bottom: 10),
  });

  final String title;
  final String subtitle;
  final NmtkTone tone;
  final IconData icon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = resolveNmtkTonePalette(context, tone);
    final theme = Theme.of(context);

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: palette.background,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(icon, size: 16, color: palette.foreground),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}