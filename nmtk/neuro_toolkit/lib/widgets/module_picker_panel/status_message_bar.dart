part of '../module_picker_panel.dart';

class _StatusMessageBar extends StatelessWidget {
  final String message;
  final NmtkTone tone;
  final String moduleName;

  const _StatusMessageBar({
    required this.message,
    required this.tone,
    required this.moduleName,
  });

  @override
  Widget build(BuildContext context) {
    final palette = resolveNmtkTonePalette(context, tone);
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: palette.foreground);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.all(
          Radius.circular(context.nmtkTokens.radiusSm),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(_toneIcon(tone), size: 12, color: palette.foreground),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle,
              ),
            ),
            const SizedBox(width: 4),
            ZetaIconButton.text(
              icon: ZetaIcons.info,
              size: ZetaWidgetSize.small,
              semanticLabel: 'Show $moduleName status details',
              onPressed: () => _showInfoDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => ZetaDialog(
        title: '$moduleName — Status',
        message: message,
        primaryButtonLabel: 'Close',
        onPrimaryButtonPressed: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  static IconData _toneIcon(NmtkTone tone) {
    switch (tone) {
      case NmtkTone.danger:
        return ZetaIcons.error_outline;
      case NmtkTone.warning:
        return ZetaIcons.warning_outline;
      case NmtkTone.info:
        return ZetaIcons.info;
      case NmtkTone.success:
        return ZetaIcons.check_circle_outline;
      case NmtkTone.neutral:
        return ZetaIcons.radio_button_unchecked;
    }
  }
}

// ---------------------------------------------------------------------------
// Progress / activity states
// ---------------------------------------------------------------------------
