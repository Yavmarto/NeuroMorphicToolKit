import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class HubPopupHeader extends StatelessWidget {
  const HubPopupHeader({
    super.key,
    required this.showingDetail,
    required this.onBack,
    required this.onClose,
    required this.navigation,
  });

  final bool showingDetail;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final Widget navigation;

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
          if (showingDetail)
            NmtkOutlinedButton(
              label: 'Back',
              icon: Icons.arrow_back,
              onPressed: onBack,
            )
          else
            Expanded(child: navigation),
          const Spacer(),
          Tooltip(
            message: 'Close NeuroHub',
            child: SizedBox(
              width: 44,
              height: 44,
              child: ZetaIconButton.text(
                icon: ZetaIcons.close,
                semanticLabel: 'Close NeuroHub',
                onPressed: onClose,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
