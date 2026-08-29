import 'package:flutter/widgets.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Applies the deployment surface's responsive outer padding.

class DeployHardwareStep extends StatelessWidget {
  const DeployHardwareStep({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < NmtkShellTokens.compactBreakpoint;
        return Padding(
          padding: compact
              ? EdgeInsets.zero
              : const EdgeInsets.fromLTRB(32, 16, 32, 32),
          child: child,
        );
      },
    );
  }
}
