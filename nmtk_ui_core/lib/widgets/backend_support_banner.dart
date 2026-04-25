import 'package:flutter/material.dart';

/// A verdict-toned banner for displaying backend support status.
///
/// The background and foreground colours are derived from [verdict]:
/// - `'faithful'` → primary container / on-primary-container
/// - `'unsupported'` → error container / on-error-container
/// - any other string → tertiary container / on-tertiary-container
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

  Color _background(ColorScheme cs) => switch (verdict) {
        'faithful' => cs.primaryContainer,
        'unsupported' => cs.errorContainer,
        _ => cs.tertiaryContainer,
      };

  Color _foreground(ColorScheme cs) => switch (verdict) {
        'faithful' => cs.onPrimaryContainer,
        'unsupported' => cs.onErrorContainer,
        _ => cs.onTertiaryContainer,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fg = _foreground(cs);

    return Container(
      margin: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: _background(cs),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: DefaultTextStyle(
        style: theme.textTheme.bodyMedium!.copyWith(color: fg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
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
                  label: Text(
                    verdict.toUpperCase(),
                    style: theme.textTheme.labelSmall,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                Text(
                  backend,
                  style: theme.textTheme.labelMedium!.copyWith(color: fg),
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
