import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';

/// Error surface used by a failed deployment workflow step.

class StepErrorPane extends StatelessWidget {
  const StepErrorPane({
    super.key,
    required this.title,
    required this.message,
    this.hint,
  });

  final String title;
  final String message;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final errorColor = AppTheme.errorColorOf(context);
    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: errorColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          border: Border.all(color: errorColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ZetaIcons.error_outline, color: errorColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Zeta.of(context).textStyles.labelMedium.copyWith(
                      color: errorColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
                color: AppTheme.textPrimary,
                height: 1.4,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons
                        .lightbulb_outline, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                    color: AppTheme.textSecondary.withValues(alpha: 0.85),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hint!,
                      style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
