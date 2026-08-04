part of '../desktop_scaffold.dart';

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
    this.brandMonogramText = 'N',
    this.brandExpandedText = 'NMTK',
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
  final String brandMonogramText;
  final String brandExpandedText;

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
            monogramText: brandMonogramText,
            expandedText: brandExpandedText,
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
              icon: ZetaIcons.settings,
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
    required this.monogramText,
    required this.expandedText,
  });

  final Widget? brand;
  final bool isExpanded;
  final VoidCallback onToggle;
  final NmtkShellMode mode;
  final String monogramText;
  final String expandedText;

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
            isExpanded ? expandedText : monogramText,
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
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
            Tooltip(
              message: 'Collapse sidebar',
              child: ZetaIconButton(
                icon: ZetaIcons.chevron_left,
                type: ZetaButtonType.text,
                size: ZetaWidgetSize.small,
                semanticLabel: 'Collapse sidebar',
                onPressed: onToggle,
              ),
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
                  color: scheme.onSurface.withValues(alpha: 0.65),
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
    final profile = widget.profile;

    return MenuAnchor(
      controller: _menuController,
      menuChildren: [
        _ProfilePopover(
          profile: profile,
          onClose: () => _menuController.close(),
        ),
      ],
      child: Tooltip(
        message: '',
        child: Semantics(
          label: profile.displayName,
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
        ? palette.accent.withValues(alpha: 0.10)
        : _hovered
        ? scheme.surfaceContainerHighest
        : null;

    final iconColor = isSelected
        ? palette.accent
        : scheme.onSurface.withValues(alpha: 0.70);

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
        borderRadius: BorderRadius.circular(tokens.radiusSm),
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
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
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
                  style: Zeta.of(context).textStyles.bodyMedium.copyWith(
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
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            child: inner,
          ),
        ),
      ),
    );
  }
}
