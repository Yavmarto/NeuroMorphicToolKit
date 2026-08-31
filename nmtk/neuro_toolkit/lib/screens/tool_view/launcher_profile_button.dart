import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub_popup.dart';

class LauncherProfileButton extends StatelessWidget {
  const LauncherProfileButton({super.key, this.iconColor});

  final Color? iconColor;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Profile',
    child: IconTheme(
      data: IconThemeData(
        color: iconColor ?? Zeta.of(context).colors.mainDefault,
      ),
      child: ZetaIconButton.text(
        icon: ZetaIcons.person,
        semanticLabel: 'Profile',
        onPressed: () => showHubPopup(context, intent: HubPopupIntent.profile),
      ),
    ),
  );
}
