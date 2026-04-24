import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/screens/dashboard.dart';
import 'package:neuro_toolkit/screens/catalog.dart';
import 'package:neuro_toolkit/screens/settings.dart';
import 'package:neuro_toolkit/screens/python_setup.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/screens/onboarding.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/providers/app_provider.dart';
import 'package:neuro_toolkit/providers/workspace_provider.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';

GoRouter createGoRouter(AppProvider appProvider) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: appProvider,
    redirect: (context, state) {
      if (!appProvider.isInitialized) return null;
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
            path: '/workspace',
            name: 'workspace',
            builder: (context, state) {
              final moduleId = state.uri.queryParameters['moduleId'];
              return ToolViewScreen(initialModuleId: moduleId);
            },
          ),
          GoRoute(
            path: '/tool/:moduleId',
            redirect: (context, state) {
              final moduleId = state.pathParameters['moduleId']!;
              return '/workspace?moduleId=$moduleId';
            },
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          // Hardware deploy routes (/deploy/akida, /deploy/pynq,
          // /deploy/teensy) were removed when the deploy UIs were relocated
          // to the Neurochip module frontend in ADR-claude/0007. Reach them
          // by opening the Neurochip module workspace.
        ],
      ),
    ],
  );
}

class MainScreen extends ConsumerWidget {
  final Widget child;
  const MainScreen({super.key, required this.child});

  List<NavigationDestinationData> _getDestinations(
      WorkspaceProvider workspace) {
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
      if (workspace.hasSessions)
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

  int _selectedIndex(BuildContext context, WorkspaceProvider workspace) {
    final location = GoRouterState.of(context).uri.toString();
    final hasWorkspace = workspace.hasSessions;
    if (location.startsWith('/catalog')) return 1;
    if (location.startsWith('/workspace') || location.startsWith('/tool/')) {
      return hasWorkspace ? 2 : 1;
    }
    if (location.startsWith('/settings')) return hasWorkspace ? 3 : 2;
    return 0;
  }

  void _onItemTapped(
    BuildContext context,
    int index,
    WorkspaceProvider workspace,
  ) {
    if (index == 0) {
      context.go('/');
    } else if (index == 1) {
      context.go('/catalog');
    } else if (index == 2) {
      if (workspace.hasSessions) {
        final focused =
            workspace.focusedModuleId ?? workspace.sessions.last.moduleId;
        context.go('/workspace?moduleId=$focused');
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
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.watch(moduleStateProvider);
    final workspace = ref.watch(workspaceStateProvider);
    final bootstrapState = ref.watch(launcherBootstrapStateProvider);

    // If Python is not available, show setup screen instead of normal UI
    if (!provider.pythonAvailable && !provider.isLoading) {
      return const PythonSetupScreen();
    }
    if (bootstrapState.status == LauncherBootstrapStatus.preflightFailed) {
      return Scaffold(
        appBar: AppBar(title: const Text('NeuroToolkit')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: NmtkShellReadinessStateView.fromState(
                NmtkShellReadinessState.error,
                message: bootstrapState.message ??
                    'Preflight failed: launcher control API could not start.',
              ),
            ),
          ),
        ),
      );
    }

    return ResponsiveScaffold(
      currentIndex: _selectedIndex(context, workspace),
      onNavigationTargetSelected: (index) =>
          _onItemTapped(context, index, workspace),
      destinations: _getDestinations(workspace),
      appBarActions: [
        NmtkTopAppBarAction(
          icon: Icons.refresh_rounded,
          label: 'Check Updates',
          tooltip: 'Check for Updates',
          onPressed: () => provider.checkForUpdates(),
        ),
      ],
      body: child,
    );
  }
}
