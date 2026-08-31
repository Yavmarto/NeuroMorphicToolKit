import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/widgets/responsive_scaffold.dart';

/// A mobile bottom navigation bar that mirrors the destination list from
/// [NmtkTopAppBar] but rendered as a [NavigationBar] at the bottom of the
/// screen.  Intended for use when `MediaQuery.sizeOf(context).width < 840`.
class NmtkMobileBottomBar extends StatelessWidget {
  const NmtkMobileBottomBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<NavigationDestinationData> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex.clamp(0, destinations.length - 1),
      onDestinationSelected: onDestinationSelected,
      destinations: [
        for (final d in destinations)
          NavigationDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon ?? d.icon),
            label: d.label,
          ),
      ],
    );
  }
}
