import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class NeurosensePopupHeader extends StatelessWidget {
  const NeurosensePopupHeader({
    super.key,
    required this.navigation,
    required this.onClose,
  });

  final Widget navigation;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.sectionGap,
        tokens.sectionGap,
        tokens.compactGap,
        tokens.sectionGap,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: navigation),
          Tooltip(
            message: 'Close NeuroSense',
            child: SizedBox(
              width: 44,
              height: 44,
              child: ZetaIconButton.text(
                icon: ZetaIcons.close,
                semanticLabel: 'Close NeuroSense',
                onPressed: onClose,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
