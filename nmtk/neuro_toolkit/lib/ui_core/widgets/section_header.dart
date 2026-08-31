import 'package:flutter/material.dart';

/// A flat, frame-less section header row used as the canonical "section divider"
/// primitive across NMTK studio surfaces.
///
/// Visual recipe (zero-decoration by design — the whole point is to *replace*
/// the heavy `NmtkSurfaceCard` frame for cases that don't need elevation):
///
/// * No background color, no border, no rounded corners.
/// * Title uses [TextTheme.titleSmall] with [FontWeight.w700] by default
///   (matches the left-side NIR Inspector header weight).
/// * Subtitle (optional) uses [TextTheme.bodyMedium] with `onSurfaceVariant`.
/// * Optional [leading] icon (size 16 by convention) sits before the title.
/// * Optional [trailing] widget (status badge, action button row) sits at the
///   far right of the header row.
///
/// Use [NmtkSectionHeader] when you only need the header row. Use [NmtkSection]
/// when you also want the standard child-column composition (header + child
/// with consistent vertical rhythm).
///
/// For genuine single-topic elevated surfaces (e.g. a result card on an empty
/// page) keep using `NmtkSurfaceCard` — but never nest it inside another card.
class NmtkSectionHeader extends StatelessWidget {
  const NmtkSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.padding = EdgeInsets.zero,
    this.titleStyle,
  });

  /// The headline text of the section.
  final String title;

  /// Optional descriptive subtitle below the title.
  final String? subtitle;

  /// Optional leading widget (typically a 16 px icon).
  final Widget? leading;

  /// Optional trailing widget (status badge, icon button, action row).
  final Widget? trailing;

  /// Padding around the header row. Defaults to `EdgeInsets.zero` so the
  /// caller can place the header flush with surrounding content.
  final EdgeInsetsGeometry padding;

  /// Override for the title [TextStyle]. Defaults to
  /// `Theme.of(context).textTheme.titleSmall.copyWith(fontWeight: w700)`.
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedTitleStyle =
        titleStyle ??
        theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 18,
        );

    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackTrailing = trailing != null && constraints.maxWidth < 360;

          final headerRow = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: resolvedTitleStyle),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null && !stackTrailing) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          );

          if (!stackTrailing) {
            return headerRow;
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              headerRow,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: trailing!),
            ],
          );
        },
      ),
    );
  }
}
