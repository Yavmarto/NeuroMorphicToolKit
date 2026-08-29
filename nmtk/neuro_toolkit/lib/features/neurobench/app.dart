import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:neuro_toolkit/features/neurobench/models/workspace_route_state.dart';
import 'package:neuro_toolkit/features/neurobench/screens/workbench_shell.dart';

final initialLocationProvider = Provider<String>(
  (ref) => '/',
  dependencies: const [],
);
final showShellChromeProvider = Provider<bool>(
  (ref) => true,
  dependencies: const [],
);

String? _legacyWorkbenchRedirect(GoRouterState state) =>
    legacyWorkbenchRedirectLocation(state.uri);

GoRouter createAppRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    redirect: (context, state) => _legacyWorkbenchRedirect(state),
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => WorkbenchShellScreen(
          routeState: NeurobenchRouteState.fromUri(state.uri),
        ),
      ),
      GoRoute(
        path: '/comparison',
        redirect: (context, state) => _legacyWorkbenchRedirect(state),
      ),
      GoRoute(
        path: '/reports',
        redirect: (context, state) => _legacyWorkbenchRedirect(state),
      ),
      GoRoute(
        path: '/robustness',
        redirect: (context, state) => _legacyWorkbenchRedirect(state),
      ),
    ],
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final initialLocation = ref.watch(initialLocationProvider);
  return createAppRouter(initialLocation: initialLocation);
}, dependencies: [initialLocationProvider]);

/// NeuroBench's routed product surface when embedded inside the root NMTK
/// application.
///
/// This widget deliberately does not create a [MaterialApp] or theme
/// provider — the root executable owns those process-wide concerns.
class NeuroBenchWorkbenchSurface extends ConsumerWidget {
  const NeuroBenchWorkbenchSurface({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return Router.withConfig(config: router);
  }
}
