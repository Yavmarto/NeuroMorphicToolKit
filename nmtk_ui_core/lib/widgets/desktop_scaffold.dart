// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:nmtk_ui_core/models/shell_models.dart';
import 'package:nmtk_ui_core/models/commands.dart';
import 'package:nmtk_ui_core/motion_tokens.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LAYOUT CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────

const double _kRailWidth = 56.0;
const double _kExpandedRailWidth = 200.0;
const double _kMobileBreakpoint = 600.0;
const double _kBrandRowHeight = 52.0;
const double _kContentHeaderHeight = 44.0;
const double _kNavItemHeight = 44.0;
const double _kNavItemRadius = 8.0;
const double _kNavItemHPad = 8.0;
const double _kNavItemVPad = 1.0;

const Duration _kSideAnimDuration = NmtkMotionTokens.durationFast;

const Duration _kBackButtonAnimDuration = NmtkMotionTokens.durationSpring;
const Curve _kBackButtonAnimCurve = NmtkMotionTokens.easeEnter;

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────

/// A single navigation destination in the [NmtkDesktopScaffold] rail.
class NmtkSidebarItem {
  const NmtkSidebarItem({
    required this.id,
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.badgeCount,
  });

  /// Stable string id used for selection tracking and accessibility labels.
  final String id;

  /// Human-readable label shown in tooltip when collapsed.
  final String label;

  final IconData icon;

  /// Icon shown in place of [icon] when this item is selected.
  final IconData? selectedIcon;

  /// When non-null and > 0, a badge with this number is shown (rail mode
  /// renders it as a small overlay since there is no label area).
  final int? badgeCount;
}

/// One entry in the [NmtkUserProfile] dropdown.
class NmtkUserProfileAction {
  const NmtkUserProfileAction({
    required String this.label,
    this.icon,
    this.onPressed,
    this.isDestructive = false,
  }) : isDivider = false;

  /// Creates a visual divider row (label and onPressed are ignored).
  const NmtkUserProfileAction.divider()
    : label = null,
      icon = null,
      onPressed = null,
      isDestructive = false,
      isDivider = true;

  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// Renders this action in the destructive colour (error).
  final bool isDestructive;

  /// When true the row renders as a [Divider] — other fields ignored.
  final bool isDivider;
}

/// User identity shown in the [NmtkDesktopScaffold] profile chip.
///
/// Pass [null] to omit the profile section entirely.
class NmtkUserProfile {
  const NmtkUserProfile({
    required this.displayName,
    this.email,
    this.avatarUrl,
    this.avatarFallback,
    this.actions = const [],
  });

  /// Primary display name ("Yoshi M.", "Admin", etc.).
  final String displayName;

  /// Optional secondary line shown below the name in the popover.
  final String? email;

  /// Remote image URL for the avatar.  Falls back to [avatarFallback].
  final String? avatarUrl;

  /// Initials shown when [avatarUrl] is null or fails to load.
  /// Defaults to the first letter of each word in [displayName].
  final String? avatarFallback;

  final List<NmtkUserProfileAction> actions;
}

// ─────────────────────────────────────────────────────────────────────────────
// FILE ACTION DELEGATE
// ─────────────────────────────────────────────────────────────────────────────

/// Abstract interface for New/Open/Save/Save-As file operations.
///
/// Provide an implementation via [NmtkDesktopScaffold.fileActions] to render
/// the file-action icon strip in [_NmtkContentHeader] and activate the
/// corresponding keyboard shortcuts (Cmd/Ctrl + N/O/S and Cmd/Ctrl+Shift+S).
abstract class NmtkFileActionDelegate {
  void onNewFile();
  void onOpenFile();
  void onSaveFile();
  void onSaveFileAs();
}

// ─────────────────────────────────────────────────────────────────────────────
// DESKTOP SCAFFOLD
// ─────────────────────────────────────────────────────────────────────────────

/// Master desktop layout for all NeuroMorphicToolKit submodules.
///
/// Phase C1 shell chrome: compact navigation rail (56 px, icon-only) with
/// collapsible sidebar support and a responsive mobile layout.
///
/// ## Layout anatomy
///
/// ```
/// ┌────┬────────────────────────────────────────┐
/// │ N  │  [← back]           [new][open][save]  │  44 px (optional)
/// │────┤────────────────────────────────────────┤
/// │nav1│                                        │
/// │nav2│   Content area  ← child →              │
/// │    │                                        │
/// │    │                                        │
/// │────┤                                        │
/// │ ⚙  │                                        │
/// │ 👤 │                                        │
/// └────┴────────────────────────────────────────┘
///  56px (collapsed) or 200px (expanded)
/// ```
///
/// ## Colour contract
///
/// All colours come from [Theme.of(context).colorScheme] — no
/// `Colors.*` references appear in this file.
///
/// | Surface                | Token                  |
/// |------------------------|------------------------|
/// | Rail                   | `scheme.surfaceContainer`          |
/// | Rail border            | `scheme.outlineVariant`        |
/// | Content header         | `scheme.surfaceContainer`          |
/// | Content header border  | `scheme.outlineVariant`        |
/// | Content area           | `scheme.surface`    |
/// | Active nav item fill   | `scheme.primary` @ 10% |
/// | Active nav icon        | `scheme.primary`       |
/// | Nav item hover         | `scheme.surfaceContainerHighest`         |
/// | Destructive actions    | `scheme.error`   |
///
/// ## Minimal usage
///
/// ```dart
/// NmtkDesktopScaffold(
///   navItems: const [
///     NmtkSidebarItem(id: 'editor',   label: 'Editor',   icon: Icons.code),
///     NmtkSidebarItem(id: 'simulate', label: 'Simulate', icon: Icons.play_arrow),
///   ],
///   selectedIndex: _index,
///   onNavItemSelected: (i) => setState(() => _index = i),
///   showBackButton: _showBack,
///   onBack: () => Navigator.of(context).pop(),
///   child: MyPageContent(),
/// )
/// ```
class NmtkDesktopScaffold extends StatefulWidget {
  const NmtkDesktopScaffold({
    super.key,
    required this.navItems,
    required this.selectedIndex,
    required this.child,
    this.onNavItemSelected,
    this.userProfile,
    this.sidebarBrand,
    this.mode = NmtkShellMode.command,
    // C1 params:
    this.showBackButton = false,
    this.onBack,
    this.fileActions,
    this.onSettingsPressed,
    // Legacy / backward-compat params:
    this.pageTitle,
    this.headerActions,
    this.footerNavItems = const [],
    this.onFooterNavItemSelected,
    this.initiallyExpanded,
  });

  /// Primary navigation items listed in the rail.
  final List<NmtkSidebarItem> navItems;

  /// Currently selected index into [navItems].
  final int selectedIndex;

  /// Page content injected by the submodule.  Fills the full content area.
  final Widget child;

  /// Called when the user taps a primary nav item.
  final ValueChanged<int>? onNavItemSelected;

  /// User profile configuration.  Pass [null] to omit the profile chip.
  final NmtkUserProfile? userProfile;

  /// Custom brand widget placed at the top of the rail.
  /// Defaults to the NMTK "N" monogram when [null].
  final Widget? sidebarBrand;

  /// Shell mode — carried through for consumers that need it.
  final NmtkShellMode mode;

  /// When true, an animated back button is shown at the top-left of the
  /// content header area.
  final bool showBackButton;

  /// Called when the user presses the back button.
  final VoidCallback? onBack;

  /// When non-null, a file-action icon strip (New / Open / Save / Save-As)
  /// is rendered in the content header, and keyboard shortcuts are active.
  final NmtkFileActionDelegate? fileActions;

  /// When non-null, a settings gear icon is shown at the bottom of the rail.
  final VoidCallback? onSettingsPressed;

  // ── Legacy / backward-compat params ──────────────────────────────────────

  /// Accepted for backward compatibility but not rendered in C1.
  final String? pageTitle;

  /// Accepted for backward compatibility but not rendered in C1.
  final Widget? headerActions;

  /// Footer nav items rendered at the bottom of the rail above the settings
  /// button and profile chip.
  final List<NmtkSidebarItem> footerNavItems;

  /// Called when the user taps a footer nav item.
  final ValueChanged<int>? onFooterNavItemSelected;

  /// When provided, the sidebar starts in expanded state.
  final bool? initiallyExpanded;

  @override
  State<NmtkDesktopScaffold> createState() => _NmtkDesktopScaffoldState();
}

class _NmtkDesktopScaffoldState extends State<NmtkDesktopScaffold> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded ?? false;
  }

  void _toggleSidebar() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        ToggleSidebarIntent: CallbackAction<ToggleSidebarIntent>(
          onInvoke: (_) => _toggleSidebar(),
        ),
      },
      child: _buildLayout(context),
    );
  }

  Widget _buildLayout(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < _kMobileBreakpoint) {
      return _buildMobileLayout(context);
    }
    return _buildDesktopLayout(context);
  }

  Widget _buildDesktopLayout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showHeader = widget.showBackButton || widget.fileActions != null;

    Widget contentColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader)
          _NmtkContentHeader(
            showBackButton: widget.showBackButton,
            onBack: widget.onBack,
            fileActions: widget.fileActions,
          ),
        Expanded(
          child: ColoredBox(color: scheme.surface, child: widget.child),
        ),
      ],
    );

    // Wrap with keyboard shortcut handling when file actions are provided.
    if (widget.fileActions != null) {
      contentColumn = _FileActionShortcuts(
        delegate: widget.fileActions!,
        child: contentColumn,
      );
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedContainer(
            duration: _kSideAnimDuration,
            width: _isExpanded ? _kExpandedRailWidth : _kRailWidth,
            child: _NmtkRailColumn(
              items: widget.navItems,
              selectedIndex: widget.selectedIndex,
              onItemSelected: widget.onNavItemSelected,
              brand: widget.sidebarBrand,
              userProfile: widget.userProfile,
              onSettingsPressed: widget.onSettingsPressed,
              footerNavItems: widget.footerNavItems,
              onFooterNavItemSelected: widget.onFooterNavItemSelected,
              isExpanded: _isExpanded,
              onToggleExpanded: _toggleSidebar,
              mode: widget.mode,
            ),
          ),
          Expanded(child: contentColumn),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mobileNavItems = _mobileNavigationItems;
    final useBottomNavigation = _shouldUseBottomNavigation;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: _NmtkMobileAppBar(
        scheme: scheme,
        title: widget.pageTitle,
        showBackButton: widget.showBackButton,
        onBack: widget.onBack,
        fileActions: widget.fileActions,
        onSettingsPressed: useBottomNavigation
            ? null
            : widget.onSettingsPressed,
        userProfile: widget.userProfile,
        showMenuButton: !useBottomNavigation,
      ),
      drawer: useBottomNavigation
          ? null
          : _NmtkMobileDrawer(
              navItems: widget.navItems,
              selectedIndex: widget.selectedIndex,
              onNavItemSelected: widget.onNavItemSelected,
              footerNavItems: widget.footerNavItems,
              onFooterNavItemSelected: widget.onFooterNavItemSelected,
              onSettingsPressed: widget.onSettingsPressed,
              userProfile: widget.userProfile,
              brand: widget.sidebarBrand,
              scheme: scheme,
              mode: widget.mode,
            ),
      body: SafeArea(
        top: false,
        child: ColoredBox(color: scheme.surface, child: widget.child),
      ),
      bottomNavigationBar: useBottomNavigation
          ? NavigationBar(
              selectedIndex: _selectedMobileNavigationIndex,
              onDestinationSelected: _handleMobileDestinationSelected,
              destinations: [
                for (final item in mobileNavItems)
                  NavigationDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon ?? item.icon),
                    label: item.label,
                  ),
              ],
            )
          : null,
    );
  }

  bool get _shouldUseBottomNavigation {
    return widget.footerNavItems.length <= 1 &&
        widget.navItems.length + widget.footerNavItems.length <= 5;
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
}

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE APP BAR
// ─────────────────────────────────────────────────────────────────────────────

class _NmtkMobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _NmtkMobileAppBar({
    required this.scheme,
    required this.showMenuButton,
    required this.showBackButton,
    this.onBack,
    this.fileActions,
    this.onSettingsPressed,
    this.userProfile,
    this.title,
  });

  final ColorScheme scheme;
  final bool showMenuButton;
  final bool showBackButton;
  final VoidCallback? onBack;
  final NmtkFileActionDelegate? fileActions;
  final VoidCallback? onSettingsPressed;
  final NmtkUserProfile? userProfile;
  final String? title;

  @override
  Size get preferredSize => const Size.fromHeight(_kContentHeaderHeight);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SizedBox(
        height: _kContentHeaderHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              if (showMenuButton)
                Builder(
                  builder: (ctx) => IconButton(
                    icon: Icon(
                      Icons.menu_rounded,
                      color: scheme.onSurface,
                      size: 20,
                    ),
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                    tooltip: 'Open navigation',
                  ),
                ),

              // Optional back arrow
              if (showBackButton)
                IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: scheme.onSurface,
                    size: 18,
                  ),
                  onPressed: onBack,
                  tooltip: 'Back',
                ),

              if (title != null && title!.isNotEmpty) ...[
                if (showMenuButton || showBackButton) const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZetaTextStyles.bodyMedium.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ] else
                const Spacer(),

              // Optional file action icons
              if (fileActions != null) ...[
                _FileActionIconButton(
                  icon: Icons.add_rounded,
                  tooltip: 'New File',
                  onPressed: fileActions!.onNewFile,
                ),
                _FileActionIconButton(
                  icon: Icons.folder_open_rounded,
                  tooltip: 'Open File',
                  onPressed: fileActions!.onOpenFile,
                ),
                _FileActionIconButton(
                  icon: Icons.save_rounded,
                  tooltip: 'Save',
                  onPressed: fileActions!.onSaveFile,
                ),
                _FileActionIconButton(
                  icon: Icons.save_as_rounded,
                  tooltip: 'Save As',
                  onPressed: fileActions!.onSaveFileAs,
                ),
              ],

              // Optional settings icon
              if (onSettingsPressed != null)
                IconButton(
                  icon: Icon(
                    Icons.settings_outlined,
                    color: scheme.onSurface.withOpacity(0.65),
                    size: 18,
                  ),
                  onPressed: onSettingsPressed,
                  tooltip: 'Settings',
                ),

              // Optional profile chip
              if (userProfile != null) _RailProfileChip(profile: userProfile!),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE DRAWER
// ─────────────────────────────────────────────────────────────────────────────

class _NmtkMobileDrawer extends StatelessWidget {
  const _NmtkMobileDrawer({
    required this.navItems,
    required this.selectedIndex,
    required this.onNavItemSelected,
    required this.footerNavItems,
    required this.onFooterNavItemSelected,
    required this.scheme,
    required this.mode,
    this.onSettingsPressed,
    this.userProfile,
    this.brand,
  });

  final List<NmtkSidebarItem> navItems;
  final int selectedIndex;
  final ValueChanged<int>? onNavItemSelected;
  final List<NmtkSidebarItem> footerNavItems;
  final ValueChanged<int>? onFooterNavItemSelected;
  final ColorScheme scheme;
  final NmtkShellMode mode;
  final VoidCallback? onSettingsPressed;
  final NmtkUserProfile? userProfile;
  final Widget? brand;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: scheme.surfaceContainer,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Brand row at top
            _RailBrandRow(
              brand: brand,
              isExpanded: true,
              onToggle: () => Navigator.of(context).pop(),
              mode: mode,
            ),
            const Divider(height: 1),

            // Primary nav items
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: _kNavItemHPad,
                  vertical: 6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < navItems.length; i++)
                      _SidebarNavItem(
                        item: navItems[i],
                        isSelected: i == selectedIndex,
                        isExpanded: true,
                        mode: mode,
                        onTap: () {
                          Navigator.of(context).pop();
                          onNavItemSelected?.call(i);
                        },
                      ),
                  ],
                ),
              ),
            ),

            // Footer nav items
            if (footerNavItems.isNotEmpty) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _kNavItemHPad,
                  vertical: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < footerNavItems.length; i++)
                      _SidebarNavItem(
                        item: footerNavItems[i],
                        isSelected: false,
                        isExpanded: true,
                        mode: mode,
                        onTap: () {
                          Navigator.of(context).pop();
                          onFooterNavItemSelected?.call(i);
                        },
                      ),
                  ],
                ),
              ),
            ],

            // Settings + profile at bottom
            const Divider(height: 1),
            if (onSettingsPressed != null)
              _RailIconButton(
                icon: Icons.settings_outlined,
                tooltip: 'Settings',
                onPressed: onSettingsPressed!,
              ),
            if (userProfile != null) _RailProfileChip(profile: userProfile!),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RAIL COLUMN
// ─────────────────────────────────────────────────────────────────────────────

class _NmtkRailColumn extends StatelessWidget {
  const _NmtkRailColumn({
    required this.items,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.mode,
    this.brand,
    this.userProfile,
    this.onSettingsPressed,
    this.footerNavItems = const [],
    this.onFooterNavItemSelected,
  });

  final List<NmtkSidebarItem> items;
  final int selectedIndex;
  final ValueChanged<int>? onItemSelected;
  final Widget? brand;
  final NmtkUserProfile? userProfile;
  final VoidCallback? onSettingsPressed;
  final List<NmtkSidebarItem> footerNavItems;
  final ValueChanged<int>? onFooterNavItemSelected;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  final NmtkShellMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Brand / logo row ──────────────────────────────────────
          _RailBrandRow(
            brand: brand,
            isExpanded: isExpanded,
            onToggle: onToggleExpanded,
            mode: mode,
          ),
          const Divider(height: 1),

          // ── Primary nav items (scrollable) ────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: _kNavItemHPad,
                vertical: 6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++)
                    _SidebarNavItem(
                      item: items[i],
                      isSelected: i == selectedIndex,
                      isExpanded: isExpanded,
                      mode: mode,
                      onTap: () => onItemSelected?.call(i),
                    ),
                ],
              ),
            ),
          ),

          // ── Footer nav items ──────────────────────────────────────
          if (footerNavItems.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _kNavItemHPad,
                vertical: 4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < footerNavItems.length; i++)
                    _SidebarNavItem(
                      item: footerNavItems[i],
                      isSelected:
                          selectedIndex < 0 &&
                          footerNavItems[i].id == 'settings',
                      isExpanded: isExpanded,
                      mode: mode,
                      onTap: () => onFooterNavItemSelected?.call(i),
                    ),
                ],
              ),
            ),
          ],

          // ── Bottom anchored: settings + profile ───────────────────
          const Divider(height: 1),
          if (onSettingsPressed != null)
            _RailIconButton(
              icon: Icons.settings_outlined,
              tooltip: 'Settings',
              onPressed: onSettingsPressed!,
            ),
          if (userProfile != null) _RailProfileChip(profile: userProfile!),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Rail brand row ─────────────────────────────────────────────────────────────

class _RailBrandRow extends StatelessWidget {
  const _RailBrandRow({
    this.brand,
    required this.isExpanded,
    required this.onToggle,
    required this.mode,
  });

  final Widget? brand;
  final bool isExpanded;
  final VoidCallback onToggle;
  final NmtkShellMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = NmtkShellTokens.of(context);
    final palette = tokens.paletteForMode(mode);

    Widget logoWidget;
    if (brand != null) {
      logoWidget = Center(child: brand!);
    } else {
      // Default NMTK logo (monogram or full)
      logoWidget = Center(
        child: AnimatedContainer(
          duration: _kSideAnimDuration,
          width: isExpanded ? 72 : 28,
          height: 28,
          decoration: BoxDecoration(
            color: palette.accent,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          alignment: Alignment.center,
          child: Text(
            isExpanded ? 'NMTK' : 'N',
            style: ZetaTextStyles.bodyMedium.copyWith(
              color: scheme.onPrimary,
              fontSize: isExpanded ? 12 : 14,
              fontWeight: FontWeight.w800,
              letterSpacing: isExpanded ? 1.0 : -0.5,
            ),
          ),
        ),
      );
    }

    if (isExpanded) {
      // Expanded: show brand on left + collapse button on right
      return SizedBox(
        height: _kBrandRowHeight,
        child: Row(
          children: [
            const SizedBox(width: 8),
            Expanded(child: logoWidget),
            IconButton(
              icon: Icon(
                Icons.chevron_left_rounded,
                color: scheme.onSurface.withOpacity(0.65),
                size: 20,
              ),
              onPressed: onToggle,
              tooltip: 'Collapse sidebar',
            ),
          ],
        ),
      );
    } else {
      // Collapsed: clicking the logo expands sidebar
      return Tooltip(
        message: 'Expand sidebar',
        child: Semantics(
          label: 'Expand sidebar',
          button: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onToggle,
              mouseCursor: SystemMouseCursors.click,
              child: SizedBox(height: _kBrandRowHeight, child: logoWidget),
            ),
          ),
        ),
      );
    }
  }
}

// ── Rail small icon button (settings, etc.) ────────────────────────────────────

class _RailIconButton extends StatefulWidget {
  const _RailIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_RailIconButton> createState() => _RailIconButtonState();
}

class _RailIconButtonState extends State<_RailIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        label: widget.tooltip,
        button: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onPressed,
            onHover: (hovered) => setState(() => _hovered = hovered),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              height: 40,
              color: _hovered ? scheme.surfaceContainerHighest : null,
              child: Center(
                child: Icon(
                  widget.icon,
                  size: 18,
                  color: scheme.onSurface.withOpacity(0.65),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Rail profile chip ──────────────────────────────────────────────────────────

class _RailProfileChip extends StatefulWidget {
  const _RailProfileChip({required this.profile});

  final NmtkUserProfile profile;

  @override
  State<_RailProfileChip> createState() => _RailProfileChipState();
}

class _RailProfileChipState extends State<_RailProfileChip> {
  final _menuController = MenuController();

  String _initials(NmtkUserProfile p) {
    if (p.avatarFallback != null) return p.avatarFallback!;
    final words = p.displayName.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) {
      return '${words.first[0]}${words.last[0]}'.toUpperCase();
    }
    final n = p.displayName;
    return (n.length >= 2 ? n.substring(0, 2) : n).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final profile = widget.profile;

    return MenuAnchor(
      controller: _menuController,
      menuChildren: [
        _ProfilePopover(
          profile: profile,
          onClose: () => _menuController.close(),
        ),
      ],
      child: Semantics(
        label: 'User profile: ${profile.displayName}',
        button: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () {
              if (_menuController.isOpen) {
                _menuController.close();
              } else {
                _menuController.open();
              }
            },
            mouseCursor: SystemMouseCursors.click,
            child: SizedBox(
              height: 40,
              child: Center(
                child: ZetaAvatar(
                  initials: _initials(profile),
                  image: profile.avatarUrl != null
                      ? Image.network(profile.avatarUrl!)
                      : null,
                  size: ZetaAvatarSize.xs,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INDIVIDUAL NAV ITEM
// ─────────────────────────────────────────────────────────────────────────────

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.item,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
    required this.mode,
  });

  final NmtkSidebarItem item;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;
  final NmtkShellMode mode;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = NmtkShellTokens.of(context);
    final palette = tokens.paletteForMode(widget.mode);
    final item = widget.item;
    final isSelected = widget.isSelected;
    final isExpanded = widget.isExpanded;

    final bgColor = isSelected
        ? palette.accent.withOpacity(0.10)
        : _hovered
        ? scheme.surfaceContainerHighest
        : null;

    final iconColor = isSelected
        ? palette.accent
        : scheme.onSurface.withOpacity(0.70);

    final textColor = isSelected ? palette.accent : scheme.onSurface;

    final effectiveIcon = isSelected
        ? (item.selectedIcon ?? item.icon)
        : item.icon;

    Widget inner = AnimatedContainer(
      duration: _kSideAnimDuration,
      height: _kNavItemHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(_kNavItemRadius),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(effectiveIcon, size: 18, color: iconColor),
          if (isExpanded) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZetaTextStyles.bodyMedium.copyWith(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (item.badgeCount != null && item.badgeCount! > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(tokens.radiusChip),
                ),
                child: Text(
                  '${item.badgeCount}',
                  style: ZetaTextStyles.bodyMedium.copyWith(
                    fontSize: 10,
                    height: 1.4,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );

    // Tooltip always shown in rail (icon-only) mode.
    if (!isExpanded) {
      inner = Tooltip(message: item.label, child: inner);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: _kNavItemVPad),
      child: Semantics(
        label: item.label,
        selected: isSelected,
        button: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            onHover: (hovered) => setState(() => _hovered = hovered),
            borderRadius: BorderRadius.circular(_kNavItemRadius),
            child: inner,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTENT HEADER (back button + file actions)
// ─────────────────────────────────────────────────────────────────────────────

/// Optional header bar rendered above the content area when [showBackButton]
/// is true or [fileActions] is provided.
class _NmtkContentHeader extends StatelessWidget {
  const _NmtkContentHeader({
    required this.showBackButton,
    this.onBack,
    this.fileActions,
  });

  final bool showBackButton;
  final VoidCallback? onBack;
  final NmtkFileActionDelegate? fileActions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SizedBox(
        height: _kContentHeaderHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              // ── Back button (animated) ──────────────────────────────
              AnimatedOpacity(
                opacity: showBackButton ? 1.0 : 0.0,
                duration: _kBackButtonAnimDuration,
                curve: _kBackButtonAnimCurve,
                child: AnimatedSlide(
                  offset: showBackButton ? Offset.zero : const Offset(-0.5, 0),
                  duration: _kBackButtonAnimDuration,
                  curve: _kBackButtonAnimCurve,
                  child: Semantics(
                    label: 'Back',
                    button: true,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      iconSize: 18,
                      tooltip: 'Back',
                      color: scheme.onSurface,
                      onPressed: showBackButton ? onBack : null,
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // ── File action icon strip ──────────────────────────────
              if (fileActions != null) ...[
                _FileActionIconButton(
                  icon: Icons.add_rounded,
                  tooltip: 'New File\n⌘N / Ctrl+N',
                  onPressed: fileActions!.onNewFile,
                ),
                _FileActionIconButton(
                  icon: Icons.folder_open_rounded,
                  tooltip: 'Open File\n⌘O / Ctrl+O',
                  onPressed: fileActions!.onOpenFile,
                ),
                _FileActionIconButton(
                  icon: Icons.save_rounded,
                  tooltip: 'Save\n⌘S / Ctrl+S',
                  onPressed: fileActions!.onSaveFile,
                ),
                _FileActionIconButton(
                  icon: Icons.save_as_rounded,
                  tooltip: 'Save As\n⌘⇧S / Ctrl+Shift+S',
                  onPressed: fileActions!.onSaveFileAs,
                ),
                const SizedBox(width: 4),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Individual file-action icon button ─────────────────────────────────────────

class _FileActionIconButton extends StatelessWidget {
  const _FileActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon),
        iconSize: 18,
        color: scheme.onSurface.withOpacity(0.75),
        tooltip: tooltip,
        onPressed: onPressed,
        splashRadius: 18,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FILE ACTION KEYBOARD SHORTCUTS
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps [child] with [CallbackShortcuts] that fire [NmtkFileActionDelegate]
/// methods on Cmd/Ctrl+N, +O, +S and Cmd/Ctrl+Shift+S.
class _FileActionShortcuts extends StatelessWidget {
  const _FileActionShortcuts({required this.delegate, required this.child});

  final NmtkFileActionDelegate delegate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
            delegate.onNewFile,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            delegate.onNewFile,
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true):
            delegate.onOpenFile,
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            delegate.onOpenFile,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            delegate.onSaveFile,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            delegate.onSaveFile,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true):
            delegate.onSaveFileAs,
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
          shift: true,
        ): delegate.onSaveFileAs,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE POPOVER CONTENT
// ─────────────────────────────────────────────────────────────────────────────

class _ProfilePopover extends StatelessWidget {
  const _ProfilePopover({required this.profile, required this.onClose});

  final NmtkUserProfile profile;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 240),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Profile header ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName,
                  style: ZetaTextStyles.bodyMedium.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                if (profile.email != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    profile.email!,
                    style: ZetaTextStyles.bodyMedium.copyWith(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Actions ───────────────────────────────────────────────
          for (final action in profile.actions)
            if (action.isDivider)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: const Divider(height: 1),
              )
            else
              _ProfileActionRow(action: action, onClose: onClose),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ProfileActionRow extends StatefulWidget {
  const _ProfileActionRow({required this.action, required this.onClose});

  final NmtkUserProfileAction action;
  final VoidCallback onClose;

  @override
  State<_ProfileActionRow> createState() => _ProfileActionRowState();
}

class _ProfileActionRowState extends State<_ProfileActionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final action = widget.action;
    final fgColor = action.isDestructive ? scheme.error : scheme.onSurface;

    return Semantics(
      label: action.label,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            widget.onClose();
            action.onPressed?.call();
          },
          onHover: (hovered) => setState(() => _hovered = hovered),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            color: _hovered ? scheme.secondary.withOpacity(0.12) : null,
            child: Row(
              children: [
                if (action.icon != null) ...[
                  Icon(action.icon, size: 15, color: fgColor.withOpacity(0.80)),
                  const SizedBox(width: 10),
                ],
                Text(
                  action.label ?? '',
                  style: ZetaTextStyles.bodyMedium.copyWith(
                    fontSize: 13,
                    color: fgColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
