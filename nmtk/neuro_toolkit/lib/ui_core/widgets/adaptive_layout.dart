import 'package:flutter/material.dart';

import 'package:neuro_toolkit/ui_core/shell_tokens.dart';

/// Renders [desktopBuilder] when available width >= [breakpoint],
/// [mobileBuilder] otherwise.
///
/// Follows the same [LayoutBuilder] pattern used by [NmtkWorkspaceShell]
/// (breakpoint 1080) and pipeline stage area (breakpoint 800).
/// Default [breakpoint] reads [NmtkShellTokens.compactBreakpoint], the same
/// mobile/tablet boundary used by [NmtkMobileScaffold], treating foldable
/// devices as mobile.
class NmtkAdaptiveLayout extends StatelessWidget {
  const NmtkAdaptiveLayout({
    super.key,
    required this.desktopBuilder,
    required this.mobileBuilder,
    this.breakpoint,
  });

  final WidgetBuilder desktopBuilder;
  final WidgetBuilder mobileBuilder;
  final double? breakpoint;

  @override
  Widget build(BuildContext context) {
    final effectiveBreakpoint =
        breakpoint ?? NmtkShellTokens.compactBreakpoint;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= effectiveBreakpoint) {
          return desktopBuilder(context);
        }
        return mobileBuilder(context);
      },
    );
  }
}
