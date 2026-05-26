import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/widgets/tone.dart';

class NmtkSurfaceCard extends StatelessWidget {
  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final NmtkTone tone;

  /// When true the child is wrapped in [Expanded] so that a [Spacer] or
  /// [Flexible] inside the child can distribute leftover space.  Requires the
  /// card to be placed inside a parent that provides a bounded height (e.g. a
  /// [SizedBox] with an explicit height).  Defaults to false for backward
  /// compatibility.
  final bool expandChild;

  /// Gap between the header row and [child]. Pass `0` to suppress the gap
  /// entirely — useful when [child] is empty or the card header is the only
  /// content.
  final double childGap;

  /// Override for the title [TextStyle]. Defaults to [TextTheme.titleMedium]
  /// with [FontWeight.w700]. Pass a smaller style (e.g. [TextTheme.titleSmall])
  /// for compact card layouts.
  final TextStyle? titleStyle;

  const NmtkSurfaceCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.all(14),
    this.tone = NmtkTone.neutral,
    this.expandChild = false,
    this.childGap = 10,
    this.titleStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final palette = resolveNmtkTonePalette(context, tone);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(
          tokens.radiusSm,
        ), // Matching NmtkShadTheme radius
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: expandChild ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (title != null ||
                subtitle != null ||
                leading != null ||
                trailing != null)
              LayoutBuilder(
                builder: (context, constraints) {
                  final stackTrailing =
                      trailing != null && constraints.maxWidth < 400;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (leading != null) ...[
                            leading!,
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (title != null)
                                  Text(
                                    title!,
                                    style:
                                        titleStyle ??
                                        theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                if (subtitle != null) ...[
                                  if (title != null) const SizedBox(height: 4),
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
                      ),
                      if (stackTrailing) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth,
                            ),
                            child: trailing!,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            if (title != null ||
                subtitle != null ||
                leading != null ||
                trailing != null)
              if (childGap > 0) SizedBox(height: childGap),
            if (expandChild) Expanded(child: child) else child,
          ],
        ),
      ),
    );
  }
}
