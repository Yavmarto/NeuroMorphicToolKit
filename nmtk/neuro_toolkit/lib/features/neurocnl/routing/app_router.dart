import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/server_config_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/canvas_host_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/studio_feature.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart'
    show neurocnlBackendDegradedProvider;

GoRouter createAppRouter({
  String initialLocation = '/',
  Widget? workspaceHeaderAction,
  required Future<void> Function() onEditServer,
  NmtkFeatureErrorReporter? onRouteError,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(showNavigationChrome: false, child: child),
        routes: [
          GoRoute(
            path: '/',
            name: 'studio',
            builder: (context, state) => StudioScreen(
              workspaceHeaderAction: workspaceHeaderAction,
              onEditServer: onEditServer,
            ),
          ),
          GoRoute(
            path: '/canvas',
            name: 'canvas',
            builder: (context, state) => CanvasHostScreen.canvas(
              projectId: state.uri.queryParameters['projectId'],
            ),
            routes: [
              GoRoute(
                path: 'projects',
                name: 'canvas-projects',
                builder: (context, state) => CanvasHostScreen.projects(
                  projectId: state.uri.queryParameters['projectId'],
                ),
              ),
              GoRoute(
                path: 'sweep',
                name: 'canvas-sweep',
                builder: (context, state) => CanvasHostScreen.sweep(
                  projectId: state.uri.queryParameters['projectId'],
                ),
              ),
              GoRoute(
                path: 'export',
                name: 'canvas-export',
                builder: (context, state) => CanvasHostScreen.export(
                  projectId: state.uri.queryParameters['projectId'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/deploy',
            // Legacy compatibility entrypoint. Studio owns deployment; this
            // route only redirects old deep links into the Studio workspace.
            redirect: (context, state) => '/?panel=deploy',
          ),
          GoRoute(
            path: '/hardware',
            redirect: (context, state) => '/?panel=hardware',
          ),
          GoRoute(
            path: '/analysis',
            redirect: (context, state) => '/?panel=analysis',
          ),
          GoRoute(
            path: '/demo/:templateId',
            name: 'demo',
            builder: (context, state) {
              final templateId = state.pathParameters['templateId'] ?? '';
              return StudioScreen(
                initialTemplateId: templateId,
                workspaceHeaderAction: workspaceHeaderAction,
                onEditServer: onEditServer,
              );
            },
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) {
      if (onRouteError != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(
            onRouteError(
              const NmtkFeatureErrorEvent(
                moduleId: NmtkModuleId.neurocnl,
                kind: NmtkFeatureErrorKind.navigation,
                message: 'NeuroStudio could not open the requested page.',
              ),
            ),
          );
        });
      }
      return Scaffold(
        body: Center(child: Text('Page not found: ${state.uri}')),
      );
    },
  );
}

/// Shell widget that provides persistent navigation (NavigationRail on desktop,
/// BottomNavigationBar on mobile) around the routed child content.
class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  final bool showNavigationChrome;

  const AppShell({
    super.key,
    required this.child,
    this.showNavigationChrome = true,
  });

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _mujocoAvailable = false;
  bool _healthLoading = true;
  bool _backendOnline = true;

  @override
  void initState() {
    super.initState();
    _checkHealth();
  }

  @override
  void dispose() {
    // Leaving the neurocnl shell: stop reporting its backend health onto the
    // shared connection dot so a stale degraded state doesn't linger.
    ref.read(neurocnlBackendDegradedProvider.notifier).set(false);
    super.dispose();
  }

  Future<void> _checkHealth() async {
    try {
      final client = ref.read(apiClientProvider);
      final result = await client.health();
      if (mounted) {
        setState(() {
          _mujocoAvailable = result.mujocoAvailable;
          _backendOnline = true;
          _healthLoading = false;
        });
      }
      _publishBackendDegraded(result.status.toLowerCase() == 'degraded');
    } catch (_) {
      if (mounted) {
        setState(() {
          _backendOnline = false;
          _healthLoading = false;
        });
      }
      _publishBackendDegraded(true);
    }
  }

  void _publishBackendDegraded(bool degraded) {
    if (!mounted) {
      return;
    }
    ref.read(neurocnlBackendDegradedProvider.notifier).set(degraded);
  }

  @override
  Widget build(BuildContext context) {
    // Re-run the health check whenever the root changes its selected backend.
    ref.listen<String?>(serverConfigProvider.select((s) => s.serverUrl), (
      prev,
      next,
    ) {
      if (next != prev) {
        _checkHealth();
      }
    });

    if (!widget.showNavigationChrome) {
      return Scaffold(
        body: SafeArea(bottom: false, child: widget.child),
      );
    }

    // No shell-level top bar: the Studio screen renders its own IDE-style
    // bar (title + stepper + file IO + single settings cog), and other
    // screens expose navigation through their own chrome. Keeping the shell
    // bar-less avoids duplicate top bars across the suite. Backend
    // readiness is reflected by the top-right connection dot, not a card
    // here (see neurocnlBackendDegradedProvider).
    return Scaffold(body: widget.child);
  }
}
