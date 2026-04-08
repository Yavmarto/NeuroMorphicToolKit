import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/screens/dashboard.dart';
import 'package:neuro_toolkit/screens/catalog.dart';
import 'package:neuro_toolkit/screens/settings.dart';
import 'package:neuro_toolkit/screens/python_setup.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/screens/onboarding.dart';
import 'package:neuro_toolkit/screens/teensy_deploy_screen.dart';
import 'package:neuro_toolkit/screens/pynq_deploy_screen.dart';
import 'package:neuro_toolkit/screens/akida_deploy_screen.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/app_provider.dart';

// ignore: avoid_dynamic_calls
final goRouter = GoRouter(
  initialLocation: '/',
  refreshListenable: AppProvider(),
  redirect: (context, state) {
    final appProvider = AppProvider();
    if (!appProvider.isInitialized) return null; // Wait for init
    if (!appProvider.hasSeenOnboarding && state.uri.path != '/onboarding') {
      return '/onboarding';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/onboarding',
      name: 'onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
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
        GoRoute(
          path: '/settings',
          name: 'settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/deploy/teensy',
          name: 'teensy-deploy',
          builder: (context, state) => const TeensyDeployScreen(),
        ),
        GoRoute(
          path: '/deploy/pynq',
          name: 'pynq-deploy',
          builder: (context, state) => const PynqDeployScreen(),
        ),
        GoRoute(
          path: '/deploy/akida',
          name: 'akida-deploy',
          builder: (context, state) => const AkidaDeployScreen(),
        ),
      ],
    ),
  ],
);

class MainScreen extends StatelessWidget {
  final Widget child;
  const MainScreen({super.key, required this.child});

  List<NavigationDestinationData> _getDestinations(ModuleProvider provider) {
    return [
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
      const NavigationDestinationData(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: 'Settings',
      ),
    ];
  }

  int _selectedIndex(BuildContext context, ModuleProvider provider) {
    final location = GoRouterState.of(context).uri.toString();
    final hasWorkspace = provider.activeModuleIds.isNotEmpty;
    if (location.startsWith('/catalog')) return 1;
    if (location.startsWith('/tool/')) return hasWorkspace ? 2 : 1;
    if (location.startsWith('/settings')) return hasWorkspace ? 3 : 2;
    return 0;
  }

  void _onItemTapped(
    BuildContext context,
    int index,
    ModuleProvider provider,
  ) {
    if (index == 0) {
      context.go('/');
    } else if (index == 1) {
      context.go('/catalog');
    } else if (index == 2) {
      if (provider.activeModuleIds.isNotEmpty) {
        context.go('/tool/${provider.activeModuleIds.last}');
      } else {
        // No workspace tab, index 2 = settings
        context.go('/settings');
      }
    } else if (index == 3) {
      // Only reachable when workspace tab is present
      context.go('/settings');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ModuleProvider>();

    // If Python is not available, show setup screen instead of normal UI
    if (!provider.pythonAvailable && !provider.isLoading) {
      return const PythonSetupScreen();
    }

    return ResponsiveScaffold(
      currentIndex: _selectedIndex(context, provider),
      onNavigationTargetSelected: (index) =>
          _onItemTapped(context, index, provider),
      destinations: _getDestinations(provider),
      body: child,
    );
  }
}
