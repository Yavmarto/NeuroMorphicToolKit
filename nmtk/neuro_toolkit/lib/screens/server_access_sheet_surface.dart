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
    final media = MediaQuery.of(context);
    // CEL-421: the sheet holds the sign-in / setup text fields, so reserve the
    // keyboard inset. The sheet body sizes to 94% of the space above the
    // keyboard and the bottom padding keeps the fields clear of it.
    final keyboardInset = media.viewInsets.bottom;
    final height = (media.size.height - keyboardInset) * 0.94;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(tokens.radiusLg),
        ),
        child: ColoredBox(
          color: colors.surfaceDefault,
          child: SizedBox(
            height: height,
            child: SafeArea(top: false, child: child),
          ),
        ),
      ),
    );
  }
}
