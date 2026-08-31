import 'package:flutter/material.dart';

/// Renders [desktopBuilder] when available width >= [breakpoint],
/// [mobileBuilder] otherwise.
///
/// Follows the same [LayoutBuilder] pattern used by [NmtkWorkspaceShell]
/// (breakpoint 1080) and pipeline stage area (breakpoint 800).
/// Default [breakpoint] of 840 matches the mobile/tablet boundary used
/// in [NmtkMobileScaffold], treating foldable devices as mobile.
class NmtkAdaptiveLayout extends StatelessWidget {
  const NmtkAdaptiveLayout({
    super.key,
    required this.desktopBuilder,
    required this.mobileBuilder,
    this.breakpoint = 840.0,
  });

  final WidgetBuilder desktopBuilder;
  final WidgetBuilder mobileBuilder;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= breakpoint) {
          return desktopBuilder(context);
        }
        return mobileBuilder(context);
      },
    );
  }
}
