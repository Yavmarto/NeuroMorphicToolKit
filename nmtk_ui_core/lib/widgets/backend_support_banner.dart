import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/widgets/tone.dart';

/// A verdict-toned banner for displaying backend support status.
///
/// The background and foreground colours are derived from [verdict] via
/// [resolveNmtkTonePalette]:
/// - `'faithful'` → [NmtkTone.success]
/// - `'unsupported'` → [NmtkTone.danger]
/// - any other string → [NmtkTone.warning]
///
/// Use [details] to pass module-specific trailing content such as fidelity
/// annotations or concept chip groups. When [compact] is true the banner
/// uses tighter padding, limits [warnings] to two entries, and omits
/// [details] entirely.
class NmtkBackendSupportBanner extends StatelessWidget {
  const NmtkBackendSupportBanner({
    super.key,
    required this.verdict,
    required this.backend,
    this.warnings = const [],
    this.title,
    this.compact = false,
    this.details,
    this.onDismiss,
  });

  /// The verdict string. Controls the banner tone.
  final String verdict;

  /// The backend identifier shown next to the verdict chip.
  final String backend;

  /// Warning strings shown as bullet items below the header row.
  /// Truncated to 2 in compact mode, 4 in full mode.
  final List<String> warnings;

  /// Optional title override. Defaults to `'Backend Support'`.
  final String? title;

  /// Whether to use compact padding and suppress [details].
  final bool compact;

  /// Optional module-specific content rendered below the warnings.
  /// Ignored when [compact] is true.
  final Widget? details;

  /// If provided, an X button is shown and this callback is invoked on tap.
  final VoidCallback? onDismiss;

  NmtkTone _tone() => switch (verdict) {
    'faithful'    => NmtkTone.success,
    'unsupported' => NmtkTone.danger,
    _             => NmtkTone.warning,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final palette = resolveNmtkTonePalette(context, _tone());
    final fg = palette.foreground;

    return Container(
      margin: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: palette.border),
      ),
      child: DefaultTextStyle(
        style: theme.textTheme.bodyMedium!.copyWith(color: fg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        title ?? 'Backend Support',
                        style: theme.textTheme.titleSmall!.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(verdict.toUpperCase()),
                        labelStyle: theme.textTheme.labelSmall!.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w700,
                        ),
                        backgroundColor: palette.background,
                        side: BorderSide(color: palette.border),
                        visualDensity: VisualDensity.compact,
                      ),
                      Text(
                        backend,
                        style: theme.textTheme.labelMedium!.copyWith(color: fg),
                      ),
                    ],
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    icon: Icon(Icons.close, size: 16, color: fg),
                    tooltip: 'Dismiss',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onDismiss,
                  ),
              ],
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final w in warnings.take(compact ? 2 : 4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $w'),
                ),
            ],
            if (!compact && details != null) details!,
          ],
        ),
      ),
    );
  }
}
