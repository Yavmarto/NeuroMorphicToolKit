import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:neuro_toolkit/ui_core/shell_tokens.dart';

/// Responsive sizing and layout helpers for modal surfaces.
///
/// ponytail: static helpers only; richer behavior belongs in
/// [NmtkContentDialog] once the shared wrapper mobile pass lands.
abstract final class NmtkDialogSurface {
  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < NmtkShellTokens.compactBreakpoint;

  /// Near-full-width on phones with [NmtkShellTokens.sectionGap] side margin.
  static BoxConstraints constraints(
    BuildContext context, {
    double maxWidth = 560,
    double? maxHeight,
  }) {
    final tokens = NmtkShellTokens.of(context);
    final size = MediaQuery.sizeOf(context);
    final insetBottom = MediaQuery.viewInsetsOf(context).bottom;
    final margin = tokens.sectionGap * 2;
    final widthCap = isCompact(context)
        ? size.width - margin
        : math.min(maxWidth, size.width - margin);
    final heightCap = maxHeight == null
        ? size.height - margin - insetBottom
        : math.min(maxHeight, size.height - margin - insetBottom);
    return BoxConstraints(
      maxWidth: widthCap.clamp(0, size.width),
      maxHeight: heightCap.clamp(0, size.height),
    );
  }

  static EdgeInsets insetPadding(BuildContext context) {
    final gap = NmtkShellTokens.of(context).sectionGap;
    return EdgeInsets.all(gap);
  }

  static EdgeInsets scrollPadding(BuildContext context) =>
      EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom);

  static Widget wrapScrollable(BuildContext context, Widget child) {
    return SingleChildScrollView(padding: scrollPadding(context), child: child);
  }

  /// Stacks actions vertically on compact when there are more than two.
  static List<Widget> layoutActions(
    BuildContext context,
    List<Widget> actions,
  ) {
    if (!isCompact(context) || actions.length <= 2) {
      return actions;
    }
    final gap = NmtkShellTokens.of(context).compactGap;
    return <Widget>[
      for (var index = 0; index < actions.length; index++) ...<Widget>[
        if (index > 0) SizedBox(height: gap),
        SizedBox(width: double.infinity, child: actions[index]),
      ],
    ];
  }
}
