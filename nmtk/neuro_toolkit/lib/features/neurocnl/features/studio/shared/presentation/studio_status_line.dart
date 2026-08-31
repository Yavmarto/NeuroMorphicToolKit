import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';

/// Inline status text used by deployment workflow panels.

class StudioStatusLine extends StatelessWidget {
  const StudioStatusLine({
    super.key,
    required this.message,
    required this.tone,
    this.loading = false,
  });

  final String message;
  final NmtkTone tone;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final color = switch (tone) {
      NmtkTone.success => tokens.healthyColor,
      NmtkTone.danger => tokens.errorColor,
      NmtkTone.warning => tokens.warningColor,
      // Resolved from the theme: the const AppTheme.textSecondary is a fixed
      // dark-theme grey and does not switch with the theme variant.
      _ => AppTheme.textSecondaryOf(context),
    };

    Widget? leading;
    if (loading) {
      leading = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
    } else if (tone == NmtkTone.success) {
      leading = Icon(ZetaIcons.check_circle_outline, size: 16, color: color);
    } else if (tone == NmtkTone.danger) {
      leading = Icon(ZetaIcons.error_outline, size: 16, color: color);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading != null) ...[
          Padding(padding: const EdgeInsets.only(top: 1), child: leading),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            message,
            style: Zeta.of(context).textStyles.bodySmall.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
