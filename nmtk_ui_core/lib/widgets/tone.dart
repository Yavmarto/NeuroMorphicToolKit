import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';

enum NmtkTone { neutral, info, success, warning, danger }

class NmtkTonePalette {
  final Color foreground;
  final Color background;
  final Color border;

  const NmtkTonePalette({
    required this.foreground,
    required this.background,
    required this.border,
  });
}

NmtkTonePalette resolveNmtkTonePalette(BuildContext context, NmtkTone tone) {
  final scheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final tokens = NmtkShellTokens.of(context);

  switch (tone) {
    case NmtkTone.neutral:
      return NmtkTonePalette(
        foreground: scheme.onSurfaceVariant,
        background: scheme.surfaceContainerHighest.withValues(alpha: 0.75),
        border: scheme.outlineVariant,
      );
    case NmtkTone.info:
      return NmtkTonePalette(
        foreground: scheme.primary,
        background: scheme.primaryContainer.withValues(alpha: 0.45),
        border: scheme.primary.withValues(alpha: 0.35),
      );
    case NmtkTone.success:
      return isDark
          ? NmtkTonePalette(
              foreground: tokens.healthyColor,
              background: tokens.healthyColor.withValues(alpha: 0.12),
              border: tokens.healthyColor.withValues(alpha: 0.35),
            )
          : const NmtkTonePalette(
              foreground: Color(0xFF1B5E20),
              background: Color(0x1F4CAF50),
              border: Color(0x664CAF50),
            );
    case NmtkTone.warning:
      return isDark
          ? NmtkTonePalette(
              foreground: tokens.warningColor,
              background: tokens.warningColor.withValues(alpha: 0.12),
              border: tokens.warningColor.withValues(alpha: 0.35),
            )
          : const NmtkTonePalette(
              foreground: Color(0xFF9A5B00),
              background: Color(0x1FF59E0B),
              border: Color(0x66F59E0B),
            );
    case NmtkTone.danger:
      return NmtkTonePalette(
        foreground: scheme.error,
        background: scheme.errorContainer.withValues(alpha: 0.55),
        border: scheme.error.withValues(alpha: 0.35),
      );
  }
}
