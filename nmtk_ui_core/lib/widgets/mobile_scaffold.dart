import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:nmtk_ui_core/models/shell_models.dart';
import 'package:nmtk_ui_core/models/scaffold_models.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/widgets/shell_chrome_scope.dart';

class NmtkMobileScaffold extends StatefulWidget {
  const NmtkMobileScaffold({
    super.key,
    required this.navItems,
    required this.selectedIndex,
    required this.child,
    this.onNavItemSelected,
    this.userProfile,
    this.sidebarBrand,
    this.mode = NmtkShellMode.command,
    this.showBackButton = false,
    this.onBack,
    this.onNewFile,
    this.onOpenFile,
    this.onSaveFile,
    this.onSaveFileAs,
    this.onSettingsPressed,
    this.pageTitle,
    this.footerNavItems = const [],
    this.onFooterNavItemSelected,
    this.showBottomNavigation = true,
  });

  final List<NmtkSidebarItem> navItems;
  final int selectedIndex;
  final Widget child;
  final ValueChanged<int>? onNavItemSelected;
  final NmtkUserProfile? userProfile;
  final Widget? sidebarBrand;
  final NmtkShellMode mode;
  final bool showBackButton;
  final VoidCallback? onBack;
  final OnNewFile? onNewFile;
  final OnOpenFile? onOpenFile;
  final OnSaveFile? onSaveFile;
  final OnSaveFileAs? onSaveFileAs;
  final VoidCallback? onSettingsPressed;
  final String? pageTitle;
  final List<NmtkSidebarItem> footerNavItems;
  final ValueChanged<int>? onFooterNavItemSelected;
  final bool showBottomNavigation;

  @override
  State<NmtkMobileScaffold> createState() => _NmtkMobileScaffoldState();
}

class _NmtkMobileScaffoldState extends State<NmtkMobileScaffold> {
  bool get _shouldUseBottomNavigation {
    final destinationCount =
        widget.navItems.length + widget.footerNavItems.length;
    return widget.footerNavItems.length <= 1 &&
        destinationCount >= 2 &&
        destinationCount <= 5;
  }

  List<NmtkSidebarItem> get _mobileNavigationItems => [
    ...widget.navItems,
    ...widget.footerNavItems,
  ];

  int get _selectedMobileNavigationIndex {
    final navCount = widget.navItems.length;
    if (widget.selectedIndex >= 0 && widget.selectedIndex < navCount) {
      return widget.selectedIndex;
    }
    if (widget.selectedIndex < 0 && widget.footerNavItems.isNotEmpty) {
      return navCount;
    }
    return 0;
  }

  void _handleMobileDestinationSelected(int index) {
    if (index < widget.navItems.length) {
      widget.onNavItemSelected?.call(index);
      return;
    }
    final footerIndex = index - widget.navItems.length;
    if (footerIndex >= 0 && footerIndex < widget.footerNavItems.length) {
      widget.onFooterNavItemSelected?.call(footerIndex);
    }
  }

  void _showFileActionsSheet() {
    // Check if any file action callback is defined
    if (widget.onNewFile == null &&
        widget.onOpenFile == null &&
        widget.onSaveFile == null &&
        widget.onSaveFileAs == null) {
      return;
    }
    // Read tokens before opening the sheet (context is valid here in the State).
    final tokens = NmtkShellTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      // P0-5 fix: radiusLg (22 px) replaces the banned raw value 24.0
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(tokens.radiusLg),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'File Actions',
                  style: Zeta.of(
                    context,
                  ).textStyles.titleLarge.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (widget.onNewFile != null)
                ZetaListItem(
                  leading: const Icon(ZetaIcons.add),
                  title: const Text('New File'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onNewFile!();
                  },
                ),
              if (widget.onOpenFile != null)
                ZetaListItem(
                  leading: const Icon(ZetaIcons.folder_outline),
                  title: const Text('Open File'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onOpenFile!();
                  },
                ),
              if (widget.onSaveFile != null)
                ZetaListItem(
                  leading: const Icon(ZetaIcons.save),
                  title: const Text('Save'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onSaveFile!();
                  },
                ),
              if (widget.onSaveFileAs != null)
                ZetaListItem(
                  leading: const Icon(ZetaIcons.save),
                  title: const Text('Save As'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onSaveFileAs!();
                  },
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final useBottomNavigation = _shouldUseBottomNavigation;
    // Show the menu button whenever there is a drawer (not using bottom
    // navigation) and there is at least one destination to show in it.
    // Even a single-item drawer should be reachable via the hamburger button
    // rather than relying on the undiscoverable left-edge swipe gesture.
    final bool showMenuButton =
        !useBottomNavigation && _mobileNavigationItems.isNotEmpty;
    final bool hasTitle =
        widget.pageTitle != null && widget.pageTitle!.isNotEmpty;
    // The 3 dots settings menu is being removed as requested.
    final bool hasAppBarContent =
        hasTitle || widget.showBackButton || showMenuButton;

    return NmtkShellChromeScope(
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: hasAppBarContent
            ? _NmtkMobileAppBar(
                scheme: scheme,
                title: widget.pageTitle,
                showBackButton: widget.showBackButton,
                onBack: widget.onBack,
                showMenuButton: showMenuButton,
              )
            : null,
        drawer: useBottomNavigation
            ? null
            : _NmtkMobileDrawer(
                navItems: widget.navItems,
                selectedIndex: widget.selectedIndex,
                onNavItemSelected: widget.onNavItemSelected,
                footerNavItems: widget.footerNavItems,
                onFooterNavItemSelected: widget.onFooterNavItemSelected,
                scheme: scheme,
                mode: widget.mode,
                brand: widget.sidebarBrand,
              ),
        body: SafeArea(
          top: false,
          child: Material(color: scheme.surface, child: widget.child),
        ),
        floatingActionButton:
            (widget.onNewFile != null ||
                widget.onOpenFile != null ||
                widget.onSaveFile != null ||
                widget.onSaveFileAs != null)
            ? FloatingActionButton(
                onPressed: _showFileActionsSheet,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                // ZETA-MIGRATION-EXEMPT: no Zeta equivalent for document-edit icon
                child: const Icon(Icons.edit_document),
              )
            : null,
        bottomNavigationBar:
            (widget.showBottomNavigation && useBottomNavigation)
            ? NavigationBar(
                selectedIndex: _selectedMobileNavigationIndex,
                onDestinationSelected: _handleMobileDestinationSelected,
                backgroundColor: scheme.surfaceContainer,
                destinations: [
                  for (final item in _mobileNavigationItems)
                    NavigationDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon ?? item.icon),
                      label: item.label,
                    ),
                ],
              )
            : null,
      ),
    );
  }
}

class _NmtkMobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _NmtkMobileAppBar({
    required this.scheme,
    required this.showMenuButton,
    required this.showBackButton,
    this.onBack,
    this.title,
  });

  final ColorScheme scheme;
  final bool showMenuButton;
  final bool showBackButton;
  final VoidCallback? onBack;
  final String? title;

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
                      icon: Icon(Icons.menu_rounded, color: scheme.onSurface),
                      iconSize: 24,
                      padding: const EdgeInsets.all(16),
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                      tooltip: 'Open navigation',
                    ),
                  ),

                if (showBackButton)
                  IconButton(
                    icon: Icon(ZetaIcons.arrow_back, color: scheme.onSurface),
                    iconSize: 24,
                    padding: const EdgeInsets.all(16),
                    onPressed: onBack,
                    tooltip: 'Back',
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
                  'NMTK',
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
