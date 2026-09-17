import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';

/// Responsive grid (1–N columns by width) for label + control rows such as
/// deploy runtime settings and NIR node parameters.
class LabeledParameterGrid extends StatelessWidget {
  const LabeledParameterGrid({
    super.key,
    required this.children,
    this.minCellWidth = 240,
    this.crossAxisSpacing = 12,
    this.mainAxisSpacing = 8,
    this.mainAxisExtent = 64,
  });

  final List<Widget> children;

  /// Minimum width per label+input cell; narrower panes get fewer columns.
  final double minCellWidth;

  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double mainAxisExtent;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate how many columns can fit, assuming each needs at least minCellWidth.
        // Cap it at a maximum of 4 items per row.
        int crossAxisCount = (constraints.maxWidth / minCellWidth).floor();
        if (crossAxisCount < 1) crossAxisCount = 1;
        if (crossAxisCount > 4) crossAxisCount = 4;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: mainAxisSpacing,
            mainAxisExtent: mainAxisExtent,
          ),
          itemCount: children.length,
          itemBuilder: (context, index) => children[index],
        );
      },
    );
  }
}

/// Inline label to the left of a compact control (e.g. [ZetaTextInput]).
class LabeledParameterRow extends StatelessWidget {
  const LabeledParameterRow({
    super.key,
    required this.label,
    required this.child,
    this.labelWidth = 140,
  });

  final String label;
  final Widget child;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );
  }
}
