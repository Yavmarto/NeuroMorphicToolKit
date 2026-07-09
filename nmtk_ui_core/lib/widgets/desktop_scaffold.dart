// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:nmtk_ui_core/models/shell_models.dart';
import 'package:nmtk_ui_core/models/commands.dart';
import 'package:nmtk_ui_core/models/scaffold_models.dart';
import 'package:nmtk_ui_core/motion_tokens.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/widgets/mobile_scaffold.dart';
import 'package:nmtk_ui_core/widgets/shell_chrome_scope.dart';

part 'desktop_scaffold/rail.dart';
part 'desktop_scaffold/content_header.dart';
part 'desktop_scaffold/profile_popover.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LAYOUT CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────

const double _kRailWidth = 56.0;
const double _kExpandedRailWidth = 200.0;
const double _kMobileBreakpoint = 840.0;
const double _kBrandRowHeight = 52.0;
const double _kContentHeaderHeight = 44.0;
const double _kNavItemHeight = 44.0;
const double _kNavItemHPad = 8.0;
const double _kNavItemVPad = 1.0;

const Duration _kSideAnimDuration = NmtkMotionTokens.durationFast;

const Duration _kBackButtonAnimDuration = NmtkMotionTokens.durationSpring;
const Curve _kBackButtonAnimCurve = NmtkMotionTokens.easeEnter;

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────

/// A single navigation destination in the [NmtkDesktopScaffold] rail.

/// One entry in the [NmtkUserProfile] dropdown.

/// User identity shown in the [NmtkDesktopScaffold] profile chip.
///
/// Pass [null] to omit the profile section entirely.

// ─────────────────────────────────────────────────────────────────────────────
// FILE ACTION DELEGATE
// ─────────────────────────────────────────────────────────────────────────────

/// Abstract interface for New/Open/Save/Save-As file operations.
///
/// Provide an implementation via [NmtkDesktopScaffold.fileActions] to render
/// the file-action icon strip in [_NmtkContentHeader] and activate the
/// corresponding keyboard shortcuts (Cmd/Ctrl + N/O/S and Cmd/Ctrl+Shift+S).

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
    this.onNewFile,
    this.onOpenFile,
    this.onSaveFile,
    this.onSaveFileAs,
    this.onSettingsPressed,
    // Legacy / backward-compat params:
    this.pageTitle,
    this.headerActions,
    this.footerNavItems = const [],
    this.onFooterNavItemSelected,
    this.initiallyExpanded,
    this.brandMonogramText = 'N',
    this.brandExpandedText = 'NMTK',
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

  /// Called when the user presses New File (Cmd/Ctrl+N).
  final OnNewFile? onNewFile;

  /// Called when the user presses Open File (Cmd/Ctrl+O).
  final OnOpenFile? onOpenFile;

  /// Called when the user presses Save (Cmd/Ctrl+S).
  final OnSaveFile? onSaveFile;

  /// Called when the user presses Save As (Cmd/Ctrl+Shift+S).
  final OnSaveFileAs? onSaveFileAs;

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

  /// Fallback monogram shown in the collapsed rail when [sidebarBrand] is
  /// null. Defaults to `'N'`.
  final String brandMonogramText;

  /// Fallback wordmark shown in the expanded rail when [sidebarBrand] is
  /// null. Defaults to `'NMTK'`.
  final String brandExpandedText;

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
      // If already inside a NmtkMobileScaffold, the outer shell provides all
      // chrome (AppBar + BottomNavigationBar). Adding another one here would
      // produce double chrome and reduce the usable content area by ~288 px on
      // a typical phone — enough to cause RenderFlex overflows.
      if (NmtkShellChromeScope.of(context)) {
        return widget.child;
      }
      return NmtkMobileScaffold(
        navItems: widget.navItems,
        selectedIndex: widget.selectedIndex,
        onNavItemSelected: widget.onNavItemSelected,
        userProfile: widget.userProfile,
        sidebarBrand: widget.sidebarBrand,
        mode: widget.mode,
        showBackButton: widget.showBackButton,
        onBack: widget.onBack,
        onNewFile: widget.onNewFile,
        onOpenFile: widget.onOpenFile,
        onSaveFile: widget.onSaveFile,
        onSaveFileAs: widget.onSaveFileAs,
        onSettingsPressed: widget.onSettingsPressed,
        pageTitle: widget.pageTitle,
        footerNavItems: widget.footerNavItems,
        onFooterNavItemSelected: widget.onFooterNavItemSelected,
        child: widget.child,
      );
    }
    return _buildDesktopLayout(context);
  }

  Widget _buildDesktopLayout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasFileActions =
        widget.onNewFile != null ||
        widget.onOpenFile != null ||
        widget.onSaveFile != null ||
        widget.onSaveFileAs != null;
    final showHeader = widget.showBackButton || hasFileActions;

    Widget contentColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader)
          _NmtkContentHeader(
            showBackButton: widget.showBackButton,
            onBack: widget.onBack,
            onNewFile: widget.onNewFile,
            onOpenFile: widget.onOpenFile,
            onSaveFile: widget.onSaveFile,
            onSaveFileAs: widget.onSaveFileAs,
          ),
        Expanded(
          child: Material(color: scheme.surface, child: widget.child),
        ),
      ],
    );

    // Wrap with keyboard shortcut handling when file actions are provided.
    if (hasFileActions) {
      contentColumn = _FileActionShortcuts(
        onNewFile: widget.onNewFile,
        onOpenFile: widget.onOpenFile,
        onSaveFile: widget.onSaveFile,
        onSaveFileAs: widget.onSaveFileAs,
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
              brandMonogramText: widget.brandMonogramText,
              brandExpandedText: widget.brandExpandedText,
            ),
          ),
          Expanded(child: contentColumn),
        ],
      ),
    );
  }
}
