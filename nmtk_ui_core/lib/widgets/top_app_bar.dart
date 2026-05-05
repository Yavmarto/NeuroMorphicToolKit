import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/app_theme.dart';
import 'package:nmtk_ui_core/models/shell_models.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';

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
            Expanded(
              child: SingleChildScrollView(
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
              ),
            ),
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
              ...actions.map((action) {
                final isSelected = action.selected;
                return Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Semantics(
                    label: action.semanticsLabel ?? action.tooltip,
                    button: true,
                    child: action.label == null
                        ? IconButton(
                            tooltip: action.tooltip,
                            style: IconButton.styleFrom(
                              backgroundColor: isSelected
                                  ? palette.accentContainer
                                  : Colors.transparent,
                              foregroundColor: isSelected
                                  ? palette.accentForeground
                                  : theme.colorScheme.onSurfaceVariant,
                              padding: const EdgeInsets.all(10),
                              minimumSize: const Size(40, 40),
                            ),
                            onPressed: action.onPressed,
                            icon: Icon(action.icon, size: 18),
                          )
                        : OutlinedButton.icon(
                            onPressed: action.onPressed,
                            icon: Icon(action.icon, size: 16),
                            label: Text(action.label!),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              minimumSize: const Size(0, 36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              side: BorderSide(
                                color: isSelected
                                    ? palette.accent.withValues(alpha: 0.35)
                                    : tokens.subtleBorder,
                              ),
                              backgroundColor: isSelected
                                  ? palette.accentContainer
                                  : theme.colorScheme.surface.withValues(
                                      alpha: 0.6,
                                    ),
                              foregroundColor: isSelected
                                  ? palette.accentForeground
                                  : theme.colorScheme.onSurfaceVariant,
                              shape: const StadiumBorder(),
                            ),
                          ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _DestinationChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color accentColor;
  final Color accentContainer;
  final Color accentForeground;
  final VoidCallback onTap;

  const _DestinationChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.accentColor,
    required this.accentContainer,
    required this.accentForeground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radiusChip),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? accentContainer
                : theme.colorScheme.surface.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(tokens.radiusChip),
            border: Border.all(
              color: isSelected
                  ? accentColor.withValues(alpha: 0.4)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 17,
                color: isSelected
                    ? accentForeground
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected
                      ? accentForeground
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
