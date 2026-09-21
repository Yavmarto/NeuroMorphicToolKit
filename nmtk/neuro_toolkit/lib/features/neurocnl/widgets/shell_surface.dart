import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class NeurocnlScreenHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const NeurocnlScreenHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final palette = tokens.paletteForMode(NmtkShellMode.studio);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: palette.frameTint,
        border: Border(bottom: BorderSide(color: tokens.subtleBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: tokens.metadataForeground,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 8),
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
        ],
      ),
    );
  }
}

class NeurocnlInfoButton extends StatelessWidget {
  const NeurocnlInfoButton({
    super.key,
    required this.title,
    required this.message,
    this.tooltip = 'More info',
  });

  final String title;
  final String message;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: ZetaIconButton.text(
        icon: ZetaIcons.info,
        size: ZetaWidgetSize.small,
        semanticLabel: tooltip,
        onPressed: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: NmtkDesignTokens.dialogShape,
            ),
            title: Text(title),
            content: NmtkDialogSurface.wrapScrollable(
              dialogContext,
              Text(
                message,
                style: Theme.of(
                  dialogContext,
                ).textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
            actions: [
              ZetaButton.text(
                onPressed: () => Navigator.of(dialogContext).pop(),
                label: 'Close',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

NmtkShellStatusSpec neurocnlStatusFromVerdict(
  String verdict, {
  String? label,
  String? detailText,
}) {
  final normalized = verdict.toLowerCase();
  return switch (normalized) {
    'faithful' => NmtkShellStatusSpec(
      label: label ?? verdict.toUpperCase(),
      tone: NmtkTone.success,
      icon: ZetaIcons.check_circle_outline,
      detailText: detailText,
    ),
    'unsupported' || 'not_deployable' => NmtkShellStatusSpec(
      label: label ?? verdict.replaceAll('_', ' ').toUpperCase(),
      tone: NmtkTone.danger,
      icon: ZetaIcons.cancel_outline,
      detailText: detailText,
    ),
    _ => NmtkShellStatusSpec(
      label: label ?? verdict.replaceAll('_', ' ').toUpperCase(),
      tone: NmtkTone.warning,
      icon: ZetaIcons.warning_outline,
      detailText: detailText,
    ),
  };
}

NmtkShellStatusSpec neurocnlStatusFromSupportState(
  String supportState, {
  String? detailText,
}) {
  final normalized = supportState.toLowerCase();
  if (normalized.contains('unsupported') ||
      normalized.contains('not_exportable') ||
      normalized.contains('failed')) {
    return NmtkShellStatusSpec(
      label: supportState.replaceAll('_', ' ').toUpperCase(),
      tone: NmtkTone.danger,
      icon: ZetaIcons.error_outline,
      detailText: detailText,
    );
  }
  if (normalized.contains('warning') ||
      normalized.contains('approximate') ||
      normalized.contains('degraded')) {
    return NmtkShellStatusSpec(
      label: supportState.replaceAll('_', ' ').toUpperCase(),
      tone: NmtkTone.warning,
      icon: ZetaIcons.warning_outline,
      detailText: detailText,
    );
  }
  return NmtkShellStatusSpec(
    label: supportState.replaceAll('_', ' ').toUpperCase(),
    tone: NmtkTone.success,
    icon: ZetaIcons.check_circle_outline,
    detailText: detailText,
  );
}

class NeurocnlMessageList extends StatelessWidget {
  final List<String> messages;
  final NmtkTone tone;
  final IconData icon;
  final EdgeInsetsGeometry padding;

  const NeurocnlMessageList({
    super.key,
    required this.messages,
    required this.tone,
    required this.icon,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final palette = resolveNmtkTonePalette(context, tone);
    return Padding(
      padding: padding,
      child: Column(
        children: messages
            .map(
              (message) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(icon, size: 16, color: palette.foreground),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
