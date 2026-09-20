import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/ui_core/models/shell_models.dart';
import 'package:neuro_toolkit/ui_core/models/scaffold_models.dart';
import 'package:neuro_toolkit/ui_core/shell_tokens.dart';
import 'package:neuro_toolkit/ui_core/widgets/shell_chrome_scope.dart';
import 'package:neuro_toolkit/ui_core/widgets/surface_card.dart';

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
    this.backTooltip = 'Back',
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

  /// Tooltip for the back button.
  final String backTooltip;

  /// Overrides the default title/back app bar with a caller-supplied
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
        final zetaColors = Zeta.of(context).colors;
        return SafeArea(
          child: NmtkSurfaceCard(
            margin: EdgeInsets.all(tokens.sectionGap),
            title: widget.fileActionsSheetTitle,
            titleStyle: Zeta.of(
              context,
            ).textStyles.titleLarge.copyWith(fontWeight: FontWeight.bold),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onNewFile != null)
                  ZetaListItem(
                    leading: Icon(ZetaIcons.add, color: zetaColors.mainDefault),
                    title: Text(widget.newFileLabel),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onNewFile!();
                    },
                  ),
                if (widget.onOpenFile != null)
                  ZetaListItem(
                    leading: Icon(
                      ZetaIcons.folder_outline,
                      color: zetaColors.mainDefault,
                    ),
                    title: Text(widget.openFileLabel),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onOpenFile!();
                    },
                  ),
                if (widget.onSaveFile != null)
                  ZetaListItem(
                    leading: Icon(
                      ZetaIcons.save,
                      color: zetaColors.mainDefault,
                    ),
                    title: Text(widget.saveFileLabel),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onSaveFile!();
                    },
                  ),
                if (widget.onSaveFileAs != null)
                  ZetaListItem(
                    leading: Icon(
                      ZetaIcons.save,
                      color: zetaColors.mainDefault,
                    ),
                    title: Text(widget.saveFileAsLabel),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onSaveFileAs!();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final navAccent = NmtkShellTokens.of(
      context,
    ).paletteForMode(widget.mode).accent;
    final useBottomNavigation = _shouldUseBottomNavigation;
    final bool hasTitle =
        widget.pageTitle != null && widget.pageTitle!.isNotEmpty;
    final bool hasAppBarContent = hasTitle || widget.showBackButton;

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
                    backTooltip: widget.backTooltip,
                  )
                : null),
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
                    child: Icon(
                      Icons.edit_document,
                      color: scheme.onPrimaryContainer,
                    ),
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
                      icon: Icon(item.icon, color: scheme.onSurfaceVariant),
                      selectedIcon: Icon(
                        item.selectedIcon ?? item.icon,
                        color: navAccent,
                      ),
                      label: item.label,
                    ),
                ],
              )
            : null,
      ),
    );
  }
}
