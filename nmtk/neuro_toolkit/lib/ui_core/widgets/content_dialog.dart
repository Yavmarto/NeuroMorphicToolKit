import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/app_theme.dart';
import 'package:neuro_toolkit/ui_core/shell_tokens.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

/// Token-aligned modal surface for rich forms and read-only content.
///
/// Zeta 1.4.5's [ZetaDialog] accepts message text only. This wrapper keeps the
/// unavoidable Flutter dialog surface inside the shared design-system package
/// while allowing callers to supply structured content and Zeta actions.
class NmtkContentDialog extends StatelessWidget {
  const NmtkContentDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const <Widget>[],
    this.maxWidth = 560,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final colors = Zeta.of(context).colors;
    return Dialog(
      backgroundColor: colors.surfaceDefault,
      shape: RoundedRectangleBorder(borderRadius: NmtkDesignTokens.dialogShape),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.all(tokens.sectionGap),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Zeta.of(context).textStyles.titleLarge),
              SizedBox(height: tokens.sectionGap),
              Flexible(child: content),
              if (actions.isNotEmpty) ...[
                SizedBox(height: tokens.sectionGap),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: tokens.compactGap,
                  runSpacing: tokens.compactGap,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
