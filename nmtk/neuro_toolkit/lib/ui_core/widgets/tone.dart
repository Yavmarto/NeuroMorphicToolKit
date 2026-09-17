import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:neuro_toolkit/ui_core/shell_tokens.dart';

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
  ZetaColors? colors;
  try {
    colors = Zeta.of(context).colors;
  } catch (_) {
    // ZetaProvider is not in the tree; fall back gracefully to NmtkShellTokens and Theme
  }

  if (colors != null) {
    switch (tone) {
      case NmtkTone.neutral:
        return NmtkTonePalette(
          foreground: colors.mainDefault,
          background: colors.surfaceDefault,
          border: colors.borderDefault,
        );
      case NmtkTone.info:
        return NmtkTonePalette(
          foreground: colors.mainInfo,
          background: colors.surfaceInfoSubtle,
          border: colors.borderInfo,
        );
      case NmtkTone.success:
        return NmtkTonePalette(
          foreground: colors.mainPositive,
          background: colors.surfacePositiveSubtle,
          border: colors.borderPositive,
        );
      case NmtkTone.warning:
        return NmtkTonePalette(
          foreground: colors.mainWarning,
          background: colors.surfaceWarningSubtle,
          border: colors.borderWarning,
        );
      case NmtkTone.danger:
        return NmtkTonePalette(
          foreground: colors.mainNegative,
          background: colors.surfaceNegativeSubtle,
          border: colors.borderNegative,
        );
    }
  }

  // Fallback to standard theme and shell tokens
  final theme = Theme.of(context);
  final tokens = NmtkShellTokens.of(context);

  switch (tone) {
    case NmtkTone.neutral:
      return NmtkTonePalette(
        foreground: theme.colorScheme.onSurface,
        background: theme.colorScheme.surfaceContainerLow,
        border: theme.colorScheme.outlineVariant,
      );
    case NmtkTone.info:
      return NmtkTonePalette(
        foreground: tokens.runningColor,
        background: tokens.runningColor.withValues(alpha: 0.12),
        border: tokens.runningColor.withValues(alpha: 0.5),
      );
    case NmtkTone.success:
      return NmtkTonePalette(
        foreground: tokens.healthyColor,
        background: tokens.healthyColor.withValues(alpha: 0.12),
        border: tokens.healthyColor.withValues(alpha: 0.5),
      );
    case NmtkTone.warning:
      return NmtkTonePalette(
        foreground: tokens.warningColor,
        background: tokens.warningColor.withValues(alpha: 0.12),
        border: tokens.warningColor.withValues(alpha: 0.5),
      );
    case NmtkTone.danger:
      return NmtkTonePalette(
        foreground: tokens.errorColor,
        background: tokens.errorColor.withValues(alpha: 0.12),
        border: tokens.errorColor.withValues(alpha: 0.5),
      );
  }
}
