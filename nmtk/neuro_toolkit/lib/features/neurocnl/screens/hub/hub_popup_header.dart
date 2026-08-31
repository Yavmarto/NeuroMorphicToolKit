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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
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
        IconButton(
          tooltip: 'Close NeuroHub',
          icon: const Icon(ZetaIcons.close),
          color: Theme.of(context).colorScheme.onSurface,
          onPressed: onClose,
        ),
      ],
    ),
  );
}
