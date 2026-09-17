import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Desktop/wide dialog surface for the server access flow.
class ServerAccessDialogSurface extends StatelessWidget {
  const ServerAccessDialogSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    return Dialog(
      backgroundColor: colors.surfaceDefault,
      shape: RoundedRectangleBorder(borderRadius: NmtkDesignTokens.dialogShape),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: SizedBox(width: 680, height: 720, child: child),
      ),
    );
  }
}
