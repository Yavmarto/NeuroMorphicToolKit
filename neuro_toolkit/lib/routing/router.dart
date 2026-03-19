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
            final provider = context.read<ModuleProvider>();
            final module = provider.modules.firstWhere((m) => m.id == moduleId);
            return ToolViewScreen(module: module);
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
    return 0;
  }

  void _onItemTapped(BuildContext context, int index) {
    if (index == 0) {
      context.go('/');
    } else {
      context.go('/catalog');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      currentIndex: _selectedIndex(context),
      onNavigationTargetSelected: (index) => _onItemTapped(context, index),
      destinations: const [
        NavigationDestinationData(
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          label: 'Dashboard',
        ),
        NavigationDestinationData(
          icon: Icons.store_outlined,
          selectedIcon: Icons.store,
          label: 'Catalog',
        ),
      ],
      body: child,
    );
  }
}
