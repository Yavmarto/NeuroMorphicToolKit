// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nmtk_ui_core/models/shell_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LAYOUT CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────

const double _kSidebarExpandedWidth  = 220.0;
const double _kSidebarCollapsedWidth = 56.0;
const double _kBrandRowHeight        = 52.0; // matches header height
const double _kHeaderHeight          = 52.0;
const double _kNavItemHeight         = 36.0;
const double _kNavItemRadius         = 8.0;  // tighter than global 12 px inside sidebar
const double _kNavItemHPad           = 8.0;
const double _kNavItemVPad           = 1.0;

const Duration _kSideAnimDuration = Duration(milliseconds: 200);
const Curve    _kSideAnimCurve    = Curves.easeInOut;

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────

/// A single navigation destination in the [NmtkDesktopScaffold] sidebar.
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

  /// Human-readable label shown when the sidebar is expanded.
  final String label;

  final IconData icon;

  /// Icon shown in place of [icon] when this item is selected.
  final IconData? selectedIcon;

  /// When non-null and > 0, a [ShadBadge] with this number is shown
  /// to the right of the label in expanded mode.
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
      : label        = null,
        icon         = null,
        onPressed    = null,
        isDestructive = false,
        isDivider    = true;

  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// Renders this action in the destructive colour (error).
  final bool isDestructive;

  /// When true the row renders as a [ShadSeparator] — other fields ignored.
  final bool isDivider;
}

/// User identity shown in the [NmtkDesktopScaffold] header.
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
// DESKTOP SCAFFOLD
// ─────────────────────────────────────────────────────────────────────────────

/// Master desktop layout for all NeuroMorphicToolKit submodules.
///
/// Replaces the previous top-tab routing pattern with a persistent left-hand
/// sidebar that provides module-level navigation.
///
/// ## Layout anatomy
///
/// ```
/// ┌──────────────────────────────────────────────────────────────┐
/// │  [Brand]  │  [Page title]              [actions] [profile]  │ 52 px
/// ├───────────┼──────────────────────────────────────────────────┤
/// │           │                                                  │
/// │  Sidebar  │   Content area  ← child →                       │
/// │  card bg  │   background token                               │
/// │           │                                                  │
/// │  [nav 1]  │                                                  │
/// │  [nav 2]  │                                                  │
/// │  ───────  │                                                  │
/// │  [foot 1] │                                                  │
/// │  [toggle] │                                                  │
/// └───────────┴──────────────────────────────────────────────────┘
/// ```
///
/// ## Colour contract
///
/// All colours are read from [ShadTheme.of(context).colorScheme] — no
/// `Colors.*` references appear in this file.
///
/// | Surface              | Token                  |
/// |----------------------|------------------------|
/// | Sidebar              | `scheme.card`          |
/// | Sidebar border       | `scheme.border`        |
/// | Header               | `scheme.card`          |
/// | Header border        | `scheme.border`        |
/// | Content area         | `scheme.background`    |
/// | Active nav item fill | `scheme.primary` @ 10% |
/// | Active nav text/icon | `scheme.primary`       |
/// | Nav item hover       | `scheme.muted`         |
/// | Destructive actions  | `scheme.destructive`   |
///
/// ## Minimal usage
///
/// ```dart
/// NmtkDesktopScaffold(
///   pageTitle: 'CNL Studio',
///   navItems: const [
///     NmtkSidebarItem(id: 'editor',   label: 'Editor',   icon: Icons.code),
///     NmtkSidebarItem(id: 'simulate', label: 'Simulate', icon: Icons.play_arrow),
///   ],
///   selectedIndex: _index,
///   onNavItemSelected: (i) => setState(() => _index = i),
///   userProfile: NmtkUserProfile(
///     displayName: 'Yoshi M.',
///     email: 'yoshi@response.nl',
///     actions: [
///       NmtkUserProfileAction(label: 'Settings', icon: Icons.settings_outlined, onPressed: _settings),
///       const NmtkUserProfileAction.divider(),
///       NmtkUserProfileAction(label: 'Sign out', icon: Icons.logout, isDestructive: true, onPressed: _signOut),
///     ],
///   ),
///   child: MyPageContent(),
/// )
/// ```
class NmtkDesktopScaffold extends StatefulWidget {
  const NmtkDesktopScaffold({
    super.key,
    required this.pageTitle,
    required this.navItems,
    required this.selectedIndex,
    required this.child,
    this.onNavItemSelected,
    this.footerNavItems = const [],
    this.onFooterNavItemSelected,
    this.headerActions,
    this.userProfile,
    this.sidebarBrand,
    this.mode = NmtkShellMode.command,
    this.initiallyExpanded = true,
  });

  /// Text shown as the current page title in the top header strip.
  final String pageTitle;

  /// Primary navigation items listed in the sidebar.
  final List<NmtkSidebarItem> navItems;

  /// Currently selected index into [navItems].
  final int selectedIndex;

  /// Called when the user taps a primary nav item.
  final ValueChanged<int>? onNavItemSelected;

  /// Optional items pinned at the bottom of the sidebar, above the collapse
  /// toggle.  These do not participate in [selectedIndex] tracking — they are
  /// utility destinations (Help, Settings, Feedback, …).
  final List<NmtkSidebarItem> footerNavItems;

  /// Called when the user taps a footer nav item (index into [footerNavItems]).
  final ValueChanged<int>? onFooterNavItemSelected;

  /// Optional widgets injected to the right of the page title in the header
  /// (left of the user profile button).
  final Widget? headerActions;

  /// User profile configuration.  Pass [null] to omit the profile button.
  final NmtkUserProfile? userProfile;

  /// Custom brand widget placed at the top of the sidebar.
  /// Defaults to an NMTK logotype mark when [null].
  final Widget? sidebarBrand;

  /// Shell mode — carried through for consumers that need it; does not
  /// directly affect scaffold colours (those come from the Shadcn scheme).
  final NmtkShellMode mode;

  /// Whether the sidebar starts in the expanded (label-visible) state.
  final bool initiallyExpanded;

  /// Page content injected by the submodule.  Fills the full content area.
  final Widget child;

  @override
  State<NmtkDesktopScaffold> createState() => _NmtkDesktopScaffoldState();
}

class _NmtkDesktopScaffoldState extends State<NmtkDesktopScaffold> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;

    return Scaffold(
      // Scaffold itself uses the Shadcn background token so any safe-area
      // insets and system bars inherit the correct surface colour.
      backgroundColor: scheme.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Left sidebar ───────────────────────────────────────────────
          _NmtkSidebarColumn(
            items:            widget.navItems,
            footerItems:      widget.footerNavItems,
            selectedIndex:    widget.selectedIndex,
            isExpanded:       _expanded,
            onItemSelected:   widget.onNavItemSelected,
            onFooterSelected: widget.onFooterNavItemSelected,
            onToggle:         () => setState(() => _expanded = !_expanded),
            brand:            widget.sidebarBrand,
          ),
          // ── Right column: header + content ─────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _NmtkDesktopHeader(
                  pageTitle:     widget.pageTitle,
                  headerActions: widget.headerActions,
                  userProfile:   widget.userProfile,
                ),
                Expanded(
                  child: ColoredBox(
                    color: scheme.background,
                    child: widget.child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SIDEBAR COLUMN
// ─────────────────────────────────────────────────────────────────────────────

class _NmtkSidebarColumn extends StatelessWidget {
  const _NmtkSidebarColumn({
    required this.items,
    required this.footerItems,
    required this.selectedIndex,
    required this.isExpanded,
    required this.onItemSelected,
    required this.onFooterSelected,
    required this.onToggle,
    this.brand,
  });

  final List<NmtkSidebarItem> items;
  final List<NmtkSidebarItem> footerItems;
  final int selectedIndex;
  final bool isExpanded;
  final ValueChanged<int>? onItemSelected;
  final ValueChanged<int>? onFooterSelected;
  final VoidCallback onToggle;
  final Widget? brand;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;

    // AnimatedContainer handles the expand/collapse width transition.
    // The inner Column always lays out at the full expanded width; we clip
    // overflow so nothing bleeds into the content area during animation.
    return AnimatedContainer(
      duration: _kSideAnimDuration,
      curve: _kSideAnimCurve,
      width: isExpanded ? _kSidebarExpandedWidth : _kSidebarCollapsedWidth,
      decoration: BoxDecoration(
        color: scheme.card,
        border: Border(right: BorderSide(color: scheme.border)),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Brand / logo row (aligned with header) ─────────────────────
          _SidebarBrandRow(isExpanded: isExpanded, brand: brand),
          const ShadSeparator.horizontal(),

          // ── Primary nav items ───────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: _kNavItemHPad,
                vertical:   6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++)
                    _SidebarNavItem(
                      item:       items[i],
                      isSelected: i == selectedIndex,
                      isExpanded: isExpanded,
                      onTap:      () => onItemSelected?.call(i),
                    ),
                ],
              ),
            ),
          ),

          // ── Footer nav items ───────────────────────────────────────────
          if (footerItems.isNotEmpty) ...[
            const ShadSeparator.horizontal(),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _kNavItemHPad,
                vertical:   6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < footerItems.length; i++)
                    _SidebarNavItem(
                      item:       footerItems[i],
                      isSelected: false,
                      isExpanded: isExpanded,
                      onTap:      () => onFooterSelected?.call(i),
                    ),
                ],
              ),
            ),
          ],

          // ── Expand / collapse toggle ────────────────────────────────────
          const ShadSeparator.horizontal(),
          _SidebarToggle(isExpanded: isExpanded, onTap: onToggle),
        ],
      ),
    );
  }
}

// ── Brand row ─────────────────────────────────────────────────────────────────

class _SidebarBrandRow extends StatelessWidget {
  const _SidebarBrandRow({required this.isExpanded, this.brand});

  final bool isExpanded;
  final Widget? brand;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;

    if (brand != null) {
      return SizedBox(
        height: _kBrandRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kNavItemHPad + 2),
          child: Align(
            alignment:
                isExpanded ? Alignment.centerLeft : Alignment.center,
            child: brand!,
          ),
        ),
      );
    }

    // Default NMTK logotype mark.
    return SizedBox(
      height: _kBrandRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kNavItemHPad + 2),
        child: Row(
          children: [
            // Filled square monogram.
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color:        scheme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                'N',
                style: TextStyle(
                  color:       scheme.primaryForeground,
                  fontSize:    14,
                  fontWeight:  FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            // Wordmark — visible only when expanded.
            if (isExpanded) ...[
              const SizedBox(width: 10),
              Text(
                'NMTK',
                style: TextStyle(
                  color:        scheme.foreground,
                  fontSize:     15,
                  fontWeight:   FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Individual nav item ────────────────────────────────────────────────────────

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.item,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
  });

  final NmtkSidebarItem item;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme     = ShadTheme.of(context).colorScheme;
    final item       = widget.item;
    final isSelected = widget.isSelected;
    final isExpanded = widget.isExpanded;

    // Background colour — only paint when needed so transparent items don't
    // show a paint call on every frame.
    final bgColor = isSelected
        ? scheme.primary.withValues(alpha: 0.10)
        : _hovered
            ? scheme.muted
            : null;

    final iconColor = isSelected
        ? scheme.primary
        : scheme.foreground.withValues(alpha: 0.70);

    final textColor = isSelected ? scheme.primary : scheme.foreground;

    final effectiveIcon =
        isSelected ? (item.selectedIcon ?? item.icon) : item.icon;

    // ── Inner content ────────────────────────────────────────────────────
    Widget inner = AnimatedContainer(
      duration: _kSideAnimDuration,
      height:   _kNavItemHeight,
      padding:  const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color:        bgColor,
        borderRadius: BorderRadius.circular(_kNavItemRadius),
      ),
      child: Row(
        children: [
          Icon(effectiveIcon, size: 18, color: iconColor),
          if (isExpanded) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                maxLines:  1,
                overflow:  TextOverflow.ellipsis,
                style: TextStyle(
                  color:      textColor,
                  fontSize:   13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (item.badgeCount != null && item.badgeCount! > 0)
              ShadBadge.secondary(
                child: Text(
                  '${item.badgeCount}',
                  style: const TextStyle(fontSize: 10, height: 1),
                ),
              ),
          ],
        ],
      ),
    );

    // Tooltip only when collapsed — label is already visible when expanded.
    if (!isExpanded) {
      inner = ShadTooltip(
        builder: (ctx) => Text(item.label),
        child:   inner,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: _kNavItemVPad),
      child: Semantics(
        label:    item.label,
        selected: isSelected,
        button:   true,
        child: MouseRegion(
          cursor:  SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit:  (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:    widget.onTap,
            child:    inner,
          ),
        ),
      ),
    );
  }
}

// ── Collapse / expand toggle ───────────────────────────────────────────────────

class _SidebarToggle extends StatefulWidget {
  const _SidebarToggle({required this.isExpanded, required this.onTap});

  final bool isExpanded;
  final VoidCallback onTap;

  @override
  State<_SidebarToggle> createState() => _SidebarToggleState();
}

class _SidebarToggleState extends State<_SidebarToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme  = ShadTheme.of(context).colorScheme;
    final icon    = widget.isExpanded
        ? Icons.chevron_left_rounded
        : Icons.chevron_right_rounded;
    final tooltip = widget.isExpanded ? 'Collapse sidebar' : 'Expand sidebar';

    return Semantics(
      label:  tooltip,
      button: true,
      child: ShadTooltip(
        builder: (ctx) => Text(tooltip),
        child: MouseRegion(
          cursor:  SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit:  (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: _kSideAnimDuration,
              height:   44,
              padding:  const EdgeInsets.symmetric(horizontal: 14),
              color:    _hovered ? scheme.muted : null,
              child: Row(
                children: [
                  Icon(
                    icon,
                    size:  18,
                    color: scheme.foreground.withValues(alpha: 0.45),
                  ),
                  if (widget.isExpanded) ...[
                    const SizedBox(width: 10),
                    Text(
                      'Collapse',
                      style: TextStyle(
                        fontSize: 12,
                        color:    scheme.foreground.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP HEADER BAR
// ─────────────────────────────────────────────────────────────────────────────

class _NmtkDesktopHeader extends StatelessWidget {
  const _NmtkDesktopHeader({
    required this.pageTitle,
    this.headerActions,
    this.userProfile,
  });

  final String pageTitle;
  final Widget? headerActions;
  final NmtkUserProfile? userProfile;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color:  scheme.card,
        border: Border(bottom: BorderSide(color: scheme.border)),
      ),
      child: SizedBox(
        height: _kHeaderHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              // ── Page title ───────────────────────────────────────────────
              Expanded(
                child: Text(
                  pageTitle,
                  maxLines:  1,
                  overflow:  TextOverflow.ellipsis,
                  style: TextStyle(
                    color:        scheme.foreground,
                    fontSize:     15,
                    fontWeight:   FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              // ── Optional header action widgets ────────────────────────────
              if (headerActions != null) ...[
                headerActions!,
                const SizedBox(width: 12),
              ],
              // ── User profile button ───────────────────────────────────────
              if (userProfile != null)
                _UserProfileButton(profile: userProfile!),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// USER PROFILE BUTTON + POPOVER
// ─────────────────────────────────────────────────────────────────────────────

class _UserProfileButton extends StatefulWidget {
  const _UserProfileButton({required this.profile});

  final NmtkUserProfile profile;

  @override
  State<_UserProfileButton> createState() => _UserProfileButtonState();
}

class _UserProfileButtonState extends State<_UserProfileButton> {
  final _popover = ShadPopoverController();

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  /// Derives two-letter initials from [NmtkUserProfile.displayName].
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
    final scheme  = ShadTheme.of(context).colorScheme;
    final profile = widget.profile;

    return ShadPopover(
      controller: _popover,
      popover: (ctx) => _ProfilePopover(
        profile: profile,
        onClose: _popover.hide,
      ),
      child: Semantics(
        label:  'User profile: ${profile.displayName}',
        button: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _popover.toggle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShadAvatar(
                  src: profile.avatarUrl,
                  child: Text(
                    _initials(profile),
                    style: TextStyle(
                      fontSize:   11,
                      fontWeight: FontWeight.w700,
                      color:      scheme.primaryForeground,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment:  MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      style: TextStyle(
                        fontSize:   13,
                        fontWeight: FontWeight.w600,
                        color:      scheme.foreground,
                      ),
                    ),
                    if (profile.email != null)
                      Text(
                        profile.email!,
                        style: TextStyle(
                          fontSize: 11,
                          color:    scheme.mutedForeground,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.unfold_more_rounded,
                  size:  14,
                  color: scheme.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE POPOVER CONTENT
// ─────────────────────────────────────────────────────────────────────────────

class _ProfilePopover extends StatelessWidget {
  const _ProfilePopover({required this.profile, required this.onClose});

  final NmtkUserProfile profile;
  final VoidCallback    onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 240),
      child: Column(
        mainAxisSize:       MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Profile header ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName,
                  style: TextStyle(
                    fontSize:   13,
                    fontWeight: FontWeight.w700,
                    color:      scheme.foreground,
                  ),
                ),
                if (profile.email != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    profile.email!,
                    style: TextStyle(fontSize: 12, color: scheme.mutedForeground),
                  ),
                ],
              ],
            ),
          ),
          const ShadSeparator.horizontal(),
          // ── Actions ───────────────────────────────────────────────────
          for (final action in profile.actions)
            if (action.isDivider)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child:   ShadSeparator.horizontal(),
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
  final VoidCallback          onClose;

  @override
  State<_ProfileActionRow> createState() => _ProfileActionRowState();
}

class _ProfileActionRowState extends State<_ProfileActionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme  = ShadTheme.of(context).colorScheme;
    final action  = widget.action;
    final fgColor = action.isDestructive
        ? scheme.destructive
        : scheme.foreground;

    return Semantics(
      label:  action.label,
      button: true,
      child: MouseRegion(
        cursor:  SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () {
            widget.onClose();
            action.onPressed?.call();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding:  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            color:    _hovered
                ? scheme.accent.withValues(alpha: 0.12)
                : null,
            child: Row(
              children: [
                if (action.icon != null) ...[
                  Icon(
                    action.icon,
                    size:  15,
                    color: fgColor.withValues(alpha: 0.80),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  action.label ?? '',
                  style: TextStyle(
                    fontSize:   13,
                    color:      fgColor,
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
