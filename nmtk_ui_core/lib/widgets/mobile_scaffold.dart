import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:nmtk_ui_core/models/shell_models.dart';
import 'package:nmtk_ui_core/models/scaffold_models.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/widgets/shell_chrome_scope.dart';

part 'mobile_scaffold_parts.dart';

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
    this.fileActionsSheetTitle = 'File Actions',
    this.newFileLabel = 'New File',
    this.openFileLabel = 'Open File',
    this.saveFileLabel = 'Save',
    this.saveFileAsLabel = 'Save As',
    this.openNavigationTooltip = 'Open navigation',
    this.backTooltip = 'Back',
    this.brandFallbackText = 'NMTK',
    this.appBar,
    this.floatingActionButton,
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

  /// Title of the modal bottom sheet shown by the file-actions FAB.
  final String fileActionsSheetTitle;

  /// Label for the "New File" action sheet item.
  final String newFileLabel;

  /// Label for the "Open File" action sheet item.
  final String openFileLabel;

  /// Label for the "Save" action sheet item.
  final String saveFileLabel;

  /// Label for the "Save As" action sheet item.
  final String saveFileAsLabel;

  /// Tooltip for the hamburger menu button that opens the drawer.
  final String openNavigationTooltip;

  /// Tooltip for the back button.
  final String backTooltip;

  /// Fallback brand text shown in the drawer header when [sidebarBrand] is
  /// null.
  final String brandFallbackText;

  /// Overrides the default title/back/menu app bar with a caller-supplied
  /// one (e.g. [NmtkTopAppBar]) — used when a screen needs consistent top
  /// chrome (like a Settings action) across both mobile and desktop layouts.
  final PreferredSizeWidget? appBar;

  /// Optional floating action button to display.
  final Widget? floatingActionButton;

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
                  widget.fileActionsSheetTitle,
                  style: Zeta.of(
                    context,
                  ).textStyles.titleLarge.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (widget.onNewFile != null)
                ZetaListItem(
                  leading: const Icon(ZetaIcons.add),
                  title: Text(widget.newFileLabel),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onNewFile!();
                  },
                ),
              if (widget.onOpenFile != null)
                ZetaListItem(
                  leading: const Icon(ZetaIcons.folder_outline),
                  title: Text(widget.openFileLabel),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onOpenFile!();
                  },
                ),
              if (widget.onSaveFile != null)
                ZetaListItem(
                  leading: const Icon(ZetaIcons.save),
                  title: Text(widget.saveFileLabel),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onSaveFile!();
                  },
                ),
              if (widget.onSaveFileAs != null)
                ZetaListItem(
                  leading: const Icon(ZetaIcons.save),
                  title: Text(widget.saveFileAsLabel),
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
        appBar:
            widget.appBar ??
            (hasAppBarContent
                ? _NmtkMobileAppBar(
                    scheme: scheme,
                    title: widget.pageTitle,
                    showBackButton: widget.showBackButton,
                    onBack: widget.onBack,
                    showMenuButton: showMenuButton,
                    openNavigationTooltip: widget.openNavigationTooltip,
                    backTooltip: widget.backTooltip,
                  )
                : null),
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
                brandFallbackText: widget.brandFallbackText,
              ),
        body: SafeArea(
          top: false,
          child: Material(color: scheme.surface, child: widget.child),
        ),
        floatingActionButton:
            widget.floatingActionButton ??
            ((widget.onNewFile != null ||
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
                : null),
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
