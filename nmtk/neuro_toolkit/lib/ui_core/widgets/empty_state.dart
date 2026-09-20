import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/widgets/surface_card.dart';
import 'package:neuro_toolkit/ui_core/widgets/tone.dart';

class NmtkEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final Widget? action;
  final NmtkTone tone;

  /// When true, uses a quieter connection-status layout: smaller icon, calmer
  /// title weight, and muted body text instead of a loud poster treatment.
  final bool compact;

  const NmtkEmptyState({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    this.action,
    this.tone = NmtkTone.neutral,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = resolveNmtkTonePalette(context, tone);

    final iconColor = compact
        ? theme.colorScheme.onSurfaceVariant
        : palette.foreground;
    final titleStyle = compact
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)
        : theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700);
    final bodyStyle = compact
        ? theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          )
        : theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 420 : 520),
        child: NmtkSurfaceCard(
          tone: compact ? NmtkTone.neutral : tone,
          padding: EdgeInsets.all(compact ? 20 : 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 24 : 52, color: iconColor),
              SizedBox(height: compact ? 12 : 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: titleStyle,
              ),
              SizedBox(height: compact ? 8 : 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: bodyStyle,
              ),
              if (action != null) ...[
                SizedBox(height: compact ? 16 : 20),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
