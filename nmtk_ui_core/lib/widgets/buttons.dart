import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/widgets/tone.dart';

class NmtkPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? leading;
  final NmtkTone tone;

  const NmtkPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.leading,
    this.tone = NmtkTone.info,
  }) : assert(
         icon == null || leading == null,
         'Provide either icon or leading, not both.',
       );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = resolveNmtkTonePalette(context, tone);
    final backgroundColor = switch (tone) {
      NmtkTone.neutral => theme.colorScheme.surfaceContainerHighest,
      NmtkTone.info => theme.colorScheme.primary,
      _ => palette.foreground,
    };
    final foregroundColor = switch (tone) {
      NmtkTone.neutral => theme.colorScheme.onSurface,
      NmtkTone.info => theme.colorScheme.onPrimary,
      _ => Colors.white,
    };
    final style = ElevatedButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
    );

    final leadingWidget =
        leading ?? (icon != null ? Icon(icon, size: 18) : null);

    if (leadingWidget != null) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: leadingWidget,
        label: Text(label),
        style: style,
      );
    }
    return ElevatedButton(
      onPressed: onPressed,
      style: style,
      child: Text(label),
    );
  }
}

class NmtkOutlinedButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? leading;
  final NmtkTone tone;

  const NmtkOutlinedButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.leading,
    this.tone = NmtkTone.neutral,
  }) : assert(
         icon == null || leading == null,
         'Provide either icon or leading, not both.',
       );

  @override
  Widget build(BuildContext context) {
    final palette = resolveNmtkTonePalette(context, tone);
    final style = OutlinedButton.styleFrom(
      foregroundColor: palette.foreground,
      side: BorderSide(color: palette.border),
      backgroundColor: palette.background.withValues(alpha: 0.18),
    );

    final leadingWidget =
        leading ?? (icon != null ? Icon(icon, size: 18) : null);

    if (leadingWidget != null) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: leadingWidget,
        label: Text(label),
        style: style,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: style,
      child: Text(label),
    );
  }
}
