import 'package:go_router/go_router.dart';

import 'package:neuro_toolkit/features/neurocnl/screens/hub/share_workspace_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/workspace_repos_screen.dart';

/// Declarative Neurohub workspace-repo routes for GoRouter.
abstract final class NeurohubRoutes {
  static const workspaces = '/neurohub/workspaces';
  static const shareWorkspace = '/neurohub/workspaces/share';
  static const workspacesName = 'neurohub-workspaces';
  static const shareWorkspaceName = 'neurohub-share-workspace';
}

List<RouteBase> neurohubRoutes() => <RouteBase>[
  GoRoute(
    path: NeurohubRoutes.workspaces,
    name: NeurohubRoutes.workspacesName,
    builder: (context, state) => const WorkspaceReposScreen(),
    routes: <RouteBase>[
      GoRoute(
        path: 'share',
        name: NeurohubRoutes.shareWorkspaceName,
        builder: (context, state) => ShareWorkspaceScreen(
          initialName: state.uri.queryParameters['name'],
        ),
      ),
    ],
  ),
];
