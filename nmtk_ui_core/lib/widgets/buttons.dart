import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/widgets/tone.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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

    final leadingWidget =
        leading ?? (icon != null ? Icon(icon, size: 18) : null);

    switch (tone) {
      case NmtkTone.danger:
        return ShadButton.destructive(
          onPressed: onPressed,
          leading: leadingWidget,
          child: Text(label),
        );
      case NmtkTone.neutral:
        return ShadButton.secondary(
          onPressed: onPressed,
          leading: leadingWidget,
          child: Text(label),
        );
      case NmtkTone.info:
      default:
        // Use primary for info or as default
        return ShadButton(
          onPressed: onPressed,
          leading: leadingWidget,
          child: Text(label),
          // If it's a non-standard tone (success/warning), we apply palette overrides
          backgroundColor: tone == NmtkTone.info ? null : palette.foreground,
          foregroundColor: tone == NmtkTone.info ? null : Colors.white,
        );
    }
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
    final leadingWidget =
        leading ?? (icon != null ? Icon(icon, size: 18) : null);

    return ShadButton.outline(
      onPressed: onPressed,
      leading: leadingWidget,
      child: Text(label),
      // Apply tone-specific outline/text colors
      foregroundColor: tone == NmtkTone.neutral ? null : palette.foreground,
      // radius: NmtkDesignTokens.buttonShape.topLeft.x, // Already handled by NmtkShadTheme
    );
  }
}
