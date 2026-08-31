import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/widgets/section_header.dart';

/// A flat, frame-less section composition: [NmtkSectionHeader] + a child
/// column with a consistent vertical gap.
///
/// This is the *default* replacement for `NeurocnlSectionCard` / hand-rolled
/// "section card" surfaces that don't need elevation — i.e. almost every
/// section heading in the right-side studio panels.
///
/// Visual recipe:
///
/// * Header rendered via [NmtkSectionHeader] (no border, no fill).
/// * [childGap] (default 12) sits between the header row and [child].
/// * No surrounding border, no surrounding background — the whole point.
class NmtkSection extends StatelessWidget {
  const NmtkSection({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    required this.child,
    this.childGap = 12,
    this.margin = EdgeInsets.zero,
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

  /// The body of the section, rendered below the header.
  final Widget child;

  /// Vertical gap between the header row and [child]. Pass `0` to remove
  /// the gap entirely.
  final double childGap;

  /// Outer margin. Defaults to `EdgeInsets.zero`.
  final EdgeInsetsGeometry margin;

  /// Inner padding around the entire `header + child` composition. Defaults
  /// to `EdgeInsets.zero` so the section flows flush with surrounding content.
  final EdgeInsetsGeometry padding;

  /// Override for the title [TextStyle].
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            NmtkSectionHeader(
              title: title,
              subtitle: subtitle,
              leading: leading,
              trailing: trailing,
              titleStyle: titleStyle,
            ),
            if (childGap > 0) SizedBox(height: childGap),
            child,
          ],
        ),
      ),
    );
  }
}
