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

  static const double _minTapTarget = 44;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final colors = Zeta.of(context).colors;
    final media = MediaQuery.of(context);
    final viewInsets = media.viewInsets;
    final margin = tokens.sectionGap;
    final isCompact = media.size.width < NmtkShellTokens.compactBreakpoint;
    final effectiveMaxWidth = isCompact
        ? media.size.width - margin * 2
        : maxWidth.clamp(0.0, media.size.width - margin * 2);
    final maxDialogHeight =
        media.size.height - viewInsets.vertical - margin * 2;
    final stackActions = isCompact && actions.length > 2;

    return Dialog(
      backgroundColor: colors.surfaceDefault,
      insetPadding: EdgeInsets.fromLTRB(
        margin,
        margin + viewInsets.top,
        margin,
        margin + viewInsets.bottom,
      ),
      shape: RoundedRectangleBorder(borderRadius: NmtkDesignTokens.dialogShape),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: effectiveMaxWidth,
            maxHeight: maxDialogHeight,
          ),
          child: Padding(
            padding: EdgeInsets.all(tokens.sectionGap),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Zeta.of(context).textStyles.titleLarge),
                SizedBox(height: tokens.sectionGap),
                Flexible(
                  child: SingleChildScrollView(
                    child: content,
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  SizedBox(height: tokens.sectionGap),
                  if (stackActions)
                    _buildStackedActions(tokens)
                  else
                    _buildWrappedActions(tokens),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWrappedActions(NmtkShellTokens tokens) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: tokens.compactGap,
      runSpacing: tokens.compactGap,
      children: actions.map(_ensureMinTapTarget).toList(),
    );
  }

  Widget _buildStackedActions(NmtkShellTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) SizedBox(height: tokens.compactGap),
          _ensureMinTapTarget(actions[i]),
        ],
      ],
    );
  }

  Widget _ensureMinTapTarget(Widget action) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _minTapTarget),
      child: action,
    );
  }
}
