import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

part 'top_app_bar_destination_chip.dart';

class NmtkTopAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? leading;
  final Widget? title;
  final List<NavigationDestinationData> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget? search;
  final List<Widget> statusBadges;
  final List<NmtkTopAppBarAction> actions;
  final NmtkShellMode mode;

  const NmtkTopAppBar({
    super.key,
    this.leading,
    this.title,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.search,
    this.statusBadges = const <Widget>[],
    this.actions = const <NmtkTopAppBarAction>[],
    this.mode = NmtkShellMode.command,
  });

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final palette = tokens.paletteForMode(mode);

    return Material(
      color: tokens.topBarBackground,
      child: Container(
        height: tokens.topAppBarHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: tokens.topBarBackground,
          border: Border(bottom: BorderSide(color: tokens.chromeBorder)),
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            if (title != null)
              Flexible(
                fit: FlexFit.loose,
                child: DefaultTextStyle(
                  style: theme.textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                  child: title!,
                ),
              ),
            if (title != null) const SizedBox(width: 14),
            Expanded(child: _buildDestinationsRow(context, palette)),
            if (search != null) ...[
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: search!,
              ),
            ],
            if (statusBadges.isNotEmpty) ...[
              const SizedBox(width: 12),
              Wrap(spacing: 8, runSpacing: 8, children: statusBadges),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 8),
              ..._buildActionItems(context, theme, palette),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDestinationsRow(
    BuildContext context,
    NmtkShellModePalette palette,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(destinations.length, (index) {
          final destination = destinations[index];
          final isSelected = selectedIndex == index;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _DestinationChip(
              label: destination.label,
              icon: isSelected
                  ? (destination.selectedIcon ?? destination.icon)
                  : destination.icon,
              isSelected: isSelected,
              accentColor: palette.accent,
              accentContainer: palette.accentContainer,
              accentForeground: palette.accentForeground,
              onTap: () => onDestinationSelected(index),
            ),
          );
        }),
      ),
    );
  }

  List<Widget> _buildActionItems(
    BuildContext context,
    ThemeData theme,
    NmtkShellModePalette palette,
  ) {
    return actions
        .map((action) {
          final isSelected = action.selected;
          return Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Semantics(
              label: action.semanticsLabel ?? action.tooltip,
              button: true,
              child: action.label == null
                  // ZETA-MIGRATION-EXEMPT: this toggle needs the shell's
                  // per-mode accent color for its selected state
                  // (palette.accentContainer/accentForeground);
                  // ZetaIconButton's `type` is a fixed semantic enum with no
                  // per-mode accent-color override.
                  ? IconButton(
                      tooltip: action.tooltip,
                      style: IconButton.styleFrom(
                        backgroundColor: isSelected
                            ? palette.accentContainer
                            : Zeta.of(
                                context,
                              ).colors.surfaceDefault.withValues(alpha: 0),
                        foregroundColor: isSelected
                            ? palette.accentForeground
                            : theme.colorScheme.onSurfaceVariant,
                        padding: const EdgeInsets.all(10),
                        minimumSize: const Size(40, 40),
                      ),
                      onPressed: action.onPressed,
                      icon: Icon(action.icon, size: 18),
                    )
                  : ZetaButton.outline(
                      label: action.label!,
                      onPressed: action.onPressed,
                      leadingIcon: action.icon,
                    ),
            ),
          );
        })
        .toList(growable: false);
  }
}
