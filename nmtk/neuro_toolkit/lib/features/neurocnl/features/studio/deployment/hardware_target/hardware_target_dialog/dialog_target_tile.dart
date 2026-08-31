import 'dart:async';

import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_target_catalog/support.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/hardware_target/hardware_target_dialog/saved_hardware_target_entry.dart';

class DialogTargetTile extends StatelessWidget {
  const DialogTargetTile({
    super.key,
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    this.onTest,
    this.testing = false,
  });

  final SavedHardwareTargetEntry entry;
  final bool selected;
  final Future<void> Function() onTap;
  final VoidCallback onEdit;

  /// Runs the connectivity test for this entry. `null` when the target type has
  /// no such check.
  final VoidCallback? onTest;
  final bool testing;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.14)
              : AppTheme.background,
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
          ),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
        child: InkWell(
          onTap: () => unawaited(onTap()),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          child: Row(
            children: [
              Icon(
                targetForId(entry.targetType).icon,
                color: AppTheme.textPrimary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          entry.title,
                          style: Zeta.of(context).textStyles.labelMedium.copyWith(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (entry.isDefault) ...[
                          const SizedBox(width: 8),
                          Icon(
                            ZetaIcons.star,
                            size: 14,
                            color: tokens.warningColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(Default)',
                            style: Zeta.of(context).textStyles.labelSmall.copyWith(
                              color: tokens.warningColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.subtitle,
                      style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTest != null)
                testing
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        key: Key('hardware-target-test-${entry.id}'),
                        tooltip: 'Test connection',
                        onPressed: onTest,
                        icon: const Icon(ZetaIcons.refresh),
                        color: AppTheme.textSecondary,
                      ),
              IconButton(
                tooltip: 'Edit target',
                onPressed: onEdit,
                icon: const Icon(ZetaIcons.edit),
                color: AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
