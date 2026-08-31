import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:neuro_toolkit/ui_core/models/shell_models.dart';
import 'package:neuro_toolkit/ui_core/shell_tokens.dart';
import 'package:neuro_toolkit/ui_core/widgets/top_app_bar.dart';

class ResponsiveScaffold extends StatelessWidget {
  final Widget body;
  final int currentIndex;
  final ValueChanged<int> onNavigationTargetSelected;
  final List<NavigationDestinationData> destinations;
  final Widget? floatingActionButton;
  final List<NmtkTopAppBarAction> appBarActions;

  /// Title shown in the wide-layout top app bar. Override for a
  /// caller-specific brand string; defaults to the suite's shell name.
  final String title;

  const ResponsiveScaffold({
    super.key,
    required this.body,
    required this.currentIndex,
    required this.onNavigationTargetSelected,
    required this.destinations,
    this.floatingActionButton,
    this.appBarActions = const <NmtkTopAppBarAction>[],
    this.title = 'NMTK Hub',
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;

        if (screenWidth < 840) {
          return Scaffold(
            body: body,
            floatingActionButton: floatingActionButton,
            bottomNavigationBar: NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: onNavigationTargetSelected,
              destinations: destinations.map((destination) {
                return NavigationDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(
                    destination.selectedIcon ?? destination.icon,
                  ),
                  label: destination.label,
                );
              }).toList(),
            ),
          );
        }

        return Scaffold(
          appBar: NmtkTopAppBar(
            leading: Container(
              key: const ValueKey('responsive-topnav-brand'),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(
                  NmtkShellTokens.of(context).radiusSm,
                ),
              ),
              child: Icon(
                ZetaIcons.memory,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: Text(title),
            destinations: destinations,
            selectedIndex: currentIndex,
            onDestinationSelected: onNavigationTargetSelected,
            actions: appBarActions,
          ),
          floatingActionButton: floatingActionButton,
          body: body,
        );
      },
    );
  }
}

/// ----------------------------------------------------------------------------
/// NAVIGATION ITEM DATACLASS
/// ----------------------------------------------------------------------------

class NavigationDestinationData {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;

  const NavigationDestinationData({
    required this.icon,
    this.selectedIcon,
    required this.label,
  });
}
