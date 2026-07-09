part of 'mobile_scaffold.dart';

class _NmtkMobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _NmtkMobileAppBar({
    required this.scheme,
    required this.showMenuButton,
    required this.showBackButton,
    required this.openNavigationTooltip,
    required this.backTooltip,
    this.onBack,
    this.title,
  });

  final ColorScheme scheme;
  final bool showMenuButton;
  final bool showBackButton;
  final VoidCallback? onBack;
  final String? title;
  final String openNavigationTooltip;
  final String backTooltip;

  @override
  Size get preferredSize => const Size.fromHeight(64.0);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                if (showMenuButton)
                  Builder(
                    builder: (ctx) => IconButton(
                      icon: Icon(
                        ZetaIcons.hamburger_menu_round,
                        color: scheme.onSurface,
                      ),
                      iconSize: 24,
                      padding: const EdgeInsets.all(16),
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                      tooltip: openNavigationTooltip,
                    ),
                  ),

                if (showBackButton)
                  IconButton(
                    icon: Icon(ZetaIcons.arrow_back, color: scheme.onSurface),
                    iconSize: 24,
                    padding: const EdgeInsets.all(16),
                    onPressed: onBack,
                    tooltip: backTooltip,
                  ),

                if (title != null && title!.isNotEmpty) ...[
                  if (showMenuButton || showBackButton)
                    const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Zeta.of(context).textStyles.titleLarge.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NmtkMobileDrawer extends StatelessWidget {
  const _NmtkMobileDrawer({
    required this.navItems,
    required this.selectedIndex,
    required this.onNavItemSelected,
    required this.footerNavItems,
    required this.onFooterNavItemSelected,
    required this.scheme,
    required this.mode,
    required this.brandFallbackText,
    this.brand,
  });

  final List<NmtkSidebarItem> navItems;
  final int selectedIndex;
  final ValueChanged<int>? onNavItemSelected;
  final List<NmtkSidebarItem> footerNavItems;
  final ValueChanged<int>? onFooterNavItemSelected;
  final ColorScheme scheme;
  final NmtkShellMode mode;
  final Widget? brand;
  final String brandFallbackText;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: scheme.surfaceContainer,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (brand != null)
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Align(alignment: Alignment.centerLeft, child: brand!),
              )
            else
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  brandFallbackText,
                  style: Zeta.of(
                    context,
                  ).textStyles.titleLarge.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    for (var i = 0; i < navItems.length; i++)
                      ZetaListItem(
                        leading: Icon(navItems[i].icon),
                        title: Text(
                          navItems[i].label,
                          style: i == selectedIndex
                              ? Zeta.of(context).textStyles.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w700,
                                )
                              : null,
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          onNavItemSelected?.call(i);
                        },
                      ),
                  ],
                ),
              ),
            ),
            if (footerNavItems.isNotEmpty) ...[
              const Divider(height: 1),
              for (var i = 0; i < footerNavItems.length; i++)
                ZetaListItem(
                  leading: Icon(footerNavItems[i].icon),
                  title: Text(footerNavItems[i].label),
                  onTap: () {
                    Navigator.of(context).pop();
                    onFooterNavItemSelected?.call(i);
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}
