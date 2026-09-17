import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

/// Overlay chip that restores the default orbit camera on the 3D brainviz.
class BrainvizResetCameraButton extends StatelessWidget {
  const BrainvizResetCameraButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radiusChip),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.background.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(tokens.radiusChip),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                ZetaIcons.refresh,
                size: 14,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Reset view',
                style: Zeta.of(context).textStyles.labelSmall.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
