import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/workflow_feature.dart';

class RunActionBar extends StatelessWidget {
  const RunActionBar({
    super.key,
    required this.isRunning,
    required this.hasErrors,
    required this.l10n,
    required this.onPlay,
    required this.onStop,
    required this.onOpenNotebook,
    required this.onRetry,
    this.isCompact = false,
    this.notebookAvailable = true,
  });

  final bool isRunning;
  final bool hasErrors;
  final bool isCompact;
  final bool notebookAvailable;
  final AppLocalizations l10n;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onOpenNotebook;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final divider = VerticalDivider(
      width: isCompact ? 12 : 24,
      thickness: 1,
      indent: 8,
      endIndent: 8,
      color: colors.borderDefault,
    );

    return Material(
      elevation: 4,
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(
        NmtkShellTokens.of(context).radiusChip,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        // Horizontally scrollable so a narrow host (a split-view pane, a
        // transient width mid-collapse-animation, a small window) shrinks
        // the visible slice instead of asserting a RenderFlex overflow —
        // this bar has no responsive/wrap fallback of its own. On compact
        // widths the icon-only buttons below already fit without scrolling;
        // this stays as the safety net for the split-pane collapse animation
        // (see its own transient-width case above).
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayStopButton(
                enabled: true,
                isRunning: isRunning,
                onPlay: onPlay,
                onStop: onStop,
                l10n: l10n,
              ),
              divider,
              IconButton(
                tooltip: notebookAvailable
                    ? 'Open notebook'
                    : 'Notebook (desktop app only)',
                icon: Icon(ZetaIcons.note, color: Zeta.of(context).colors.mainDefault),
                onPressed: notebookAvailable ? onOpenNotebook : null,
              ),
              if (hasErrors) ...[
                divider,
                isCompact
                    ? IconButton(
                        tooltip: 'Retry',
                        onPressed: onRetry,
                        icon: Icon(
                          ZetaIcons.refresh,
                          size: 18,
                          color: colors.mainNegative,
                        ),
                      )
                    : TextButton.icon(
                        onPressed: onRetry,
                        icon: Icon(
                          ZetaIcons.refresh,
                          size: 18,
                          color: colors.mainNegative,
                        ),
                        label: Text(
                          'Retry',
                          style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                            color: colors.mainNegative,
                          ),
                        ),
                      ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
