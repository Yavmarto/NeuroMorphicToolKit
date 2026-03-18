import 'package:flutter/material.dart';
import '../app_theme.dart';

/// A customized NavigationRail matching NMTK design patterns.
///
/// This component follows Material 3 desktop patterns and integrates
/// with [NmtkDesignTokens] for consistent branding.
class NmtkNavigationRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestinationData> destinations;
  final Widget? leading;
  final Widget? trailing;
  final bool extended;
  final NavigationRailLabelType labelType;

  const NmtkNavigationRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.leading,
    this.trailing,
    this.extended = false,
    this.labelType = NavigationRailLabelType.selected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      extended: extended,
      labelType: labelType,
      backgroundColor: theme.navigationRailTheme.backgroundColor,
      indicatorColor: theme.colorScheme.primaryContainer,
      indicatorShape: theme.navigationRailTheme.indicatorShape,
      leading: leading,
      trailing: trailing,
      destinations: destinations.map((d) {
        return NavigationRailDestination(
          icon: Icon(d.icon),
          selectedIcon: Icon(d.selectedIcon ?? d.icon),
          label: Text(d.label),
        );
      }).toList(),
    );
  }
}
