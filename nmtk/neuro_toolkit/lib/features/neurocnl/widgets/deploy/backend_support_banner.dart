import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:neuro_toolkit/ui_core/shell_tokens.dart';
import 'package:neuro_toolkit/ui_core/widgets/status_badge.dart';
import 'package:neuro_toolkit/ui_core/widgets/tone.dart';

/// NeuroCNL's verdict-toned banner for displaying backend support status.
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
    'faithful' => NmtkTone.success,
    'unsupported' => NmtkTone.danger,
    _ => NmtkTone.warning,
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
                      // NmtkStatusBadge (not a raw Chip) so the verdict pill
                      // keeps the same tone-driven palette as the banner
                      // itself — a generic ZetaAssistChip has no per-instance
                      // tone/color param and would flatten this to one color.
                      NmtkStatusBadge(
                        label: verdict.toUpperCase(),
                        tone: _tone(),
                      ),
                      Text(
                        backend,
                        style: theme.textTheme.labelMedium!.copyWith(color: fg),
                      ),
                    ],
                  ),
                ),
                if (onDismiss != null)
                  // ZetaIconButton has no hover-tooltip param, so the
                  // Material Tooltip wrapper is kept purely for that
                  // affordance while the button chrome itself is Zeta.
                  Tooltip(
                    message: 'Dismiss',
                    child: ZetaIconButton(
                      icon: ZetaIcons.close,
                      size: ZetaWidgetSize.small,
                      type: ZetaButtonType.text,
                      semanticLabel: 'Dismiss',
                      onPressed: onDismiss,
                    ),
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
