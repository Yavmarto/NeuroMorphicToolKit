import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Desktop/wide dialog surface for the server access flow.
class ServerAccessDialogSurface extends StatelessWidget {
  const ServerAccessDialogSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    // CEL-421: cap the surface to the viewport instead of a fixed 680x720 so a
    // short desktop window cannot clip the form. Width stays at the desktop
    // 680 cap because this surface is only shown at/above compactBreakpoint.
    final constraints = NmtkDialogSurface.constraints(
      context,
      maxWidth: 680,
      maxHeight: 720,
    );
    return Dialog(
      backgroundColor: colors.surfaceDefault,
      shape: RoundedRectangleBorder(borderRadius: NmtkDesignTokens.dialogShape),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: constraints,
        child: SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: SafeArea(child: child),
        ),
      ),
    );
  }
}
