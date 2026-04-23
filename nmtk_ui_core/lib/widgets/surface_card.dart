import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/app_theme.dart';
import 'package:nmtk_ui_core/widgets/tone.dart';

class NmtkSurfaceCard extends StatelessWidget {
  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final NmtkTone tone;

  const NmtkSurfaceCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.all(20),
    this.tone = NmtkTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = resolveNmtkTonePalette(context, tone);
    final isNeutral = tone == NmtkTone.neutral;

    return Card(
      margin: margin,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: isNeutral ? theme.colorScheme.surface : palette.background,
      shape: RoundedRectangleBorder(
        borderRadius: NmtkDesignTokens.cardShape,
        side: BorderSide(
          color: isNeutral
              ? theme.colorScheme.outlineVariant.withValues(alpha: 0.65)
              : palette.border,
        ),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null ||
                subtitle != null ||
                leading != null ||
                trailing != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 12)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null)
                          Text(
                            title!,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        if (subtitle != null) ...[
                          if (title != null) const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
            if (title != null ||
                subtitle != null ||
                leading != null ||
                trailing != null)
              const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
