import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Phone bottom-sheet surface for the server access flow.
class ServerAccessSheetSurface extends StatelessWidget {
  const ServerAccessSheetSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final colors = Zeta.of(context).colors;
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(tokens.radiusLg),
      ),
      child: ColoredBox(
        color: colors.surfaceDefault,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.94,
          child: SafeArea(top: false, child: child),
        ),
      ),
    );
  }
}
