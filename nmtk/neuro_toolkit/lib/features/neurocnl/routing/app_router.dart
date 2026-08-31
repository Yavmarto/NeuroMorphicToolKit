import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/server_config_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/canvas_host_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/studio_feature.dart';

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
    } catch (_) {
      if (mounted) {
        setState(() {
          _backendOnline = false;
          _healthLoading = false;
        });
      }
    }
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

    final status = _buildShellStatus();
    final readiness = _buildReadinessCard(status);

    if (!widget.showNavigationChrome) {
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (readiness != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: readiness,
                ),
              Expanded(child: widget.child),
            ],
          ),
        ),
      );
    }

    // No shell-level top bar: the Studio screen renders its own IDE-style
    // bar (title + stepper + file IO + single settings cog), and other
    // screens expose navigation through their own chrome. Keeping the shell
    // bar-less avoids duplicate top bars across the suite.
    return Scaffold(
      body: Column(
        children: [
          if (readiness != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: readiness,
            ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  NmtkShellStatusSpec _buildShellStatus() {
    if (_healthLoading) {
      return NmtkShellStatusSpec.fromReadinessState(
        NmtkShellReadinessState.warmingUp,
        detailText: 'Checking backend readiness for the authoring workspace.',
      );
    }
    if (_backendOnline) {
      return NmtkShellStatusSpec.fromReadinessState(
        NmtkShellReadinessState.ready,
        detailText: _mujocoAvailable
            ? 'Authoring, diagnostics, and simulation services are available.'
            : 'Core authoring is ready. Some advanced diagnostics remain degraded.',
      );
    }
    return NmtkShellStatusSpec.fromReadinessState(
      NmtkShellReadinessState.degraded,
      detailText: 'Backend unreachable. Cached authoring remains available.',
    );
  }

  Widget? _buildReadinessCard(NmtkShellStatusSpec status) {
    if (_backendOnline && !_healthLoading) {
      return null;
    }
    final state = _healthLoading
        ? NmtkShellReadinessState.warmingUp
        : NmtkShellReadinessState.degraded;
    return NmtkShellReadinessStateView.fromState(
      state,
      message: status.detailText,
      action: !_healthLoading
          ? NmtkShellRetryButton(onPressed: _checkHealth)
          : null,
    );
  }
}
