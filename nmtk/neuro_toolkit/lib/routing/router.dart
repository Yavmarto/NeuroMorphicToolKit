import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/screens/dashboard.dart';
import 'package:neuro_toolkit/screens/catalog.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';

final goRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => MainScreen(child: child),
      routes: [
        GoRoute(
          path: '/',
          name: 'dashboard',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/catalog',
          name: 'catalog',
          builder: (context, state) => const CatalogScreen(),
        ),
        GoRoute(
          path: '/tool/:moduleId',
          name: 'tool',
          builder: (context, state) {
            final moduleId = state.pathParameters['moduleId']!;
            return ToolViewScreen(initialModuleId: moduleId);
          },
        ),
      ],
    ),
  ],
);

class MainScreen extends StatelessWidget {
  final Widget child;
  const MainScreen({super.key, required this.child});

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/catalog')) return 1;
    if (location.startsWith('/tool/')) return 2;
    return 0;
  }

  void _onItemTapped(BuildContext context, int index) {
    if (index == 0) {
      context.go('/');
    } else if (index == 1) {
      context.go('/catalog');
    } else if (index == 2) {
      final provider = context.read<ModuleProvider>();
      if (provider.activeModuleIds.isNotEmpty) {
        context.go('/tool/${provider.activeModuleIds.last}');
      } else {
        context.go('/');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ModuleProvider>();
    return ResponsiveScaffold(
      currentIndex: _selectedIndex(context),
      onNavigationTargetSelected: (index) => _onItemTapped(context, index),
      destinations: [
        const NavigationDestinationData(
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          label: 'Dashboard',
        ),
        const NavigationDestinationData(
          icon: Icons.store_outlined,
          selectedIcon: Icons.store,
          label: 'Catalog',
        ),
        if (provider.activeModuleIds.isNotEmpty)
          const NavigationDestinationData(
            icon: Icons.laptop_outlined,
            selectedIcon: Icons.laptop,
            label: 'Workspace',
          ),
      ],
      body: child,
    );
  }
}
