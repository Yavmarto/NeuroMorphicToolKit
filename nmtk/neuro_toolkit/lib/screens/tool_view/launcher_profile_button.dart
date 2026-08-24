part of '../tool_view.dart';

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
            onPressed: () => showHubPopup(
              context,
              intent: HubPopupIntent.profile,
            ),
          ),
        ),
      );
}
