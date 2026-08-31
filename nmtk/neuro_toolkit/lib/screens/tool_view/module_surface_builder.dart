import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/widgets/connection_error_actions.dart';
import 'package:neuro_toolkit/widgets/module_loading_view.dart';
import 'package:neuro_toolkit/workspace/native_surface_registry.dart';

import 'package:neuro_toolkit/screens/tool_view/cross_module_navigation.dart';
import 'package:neuro_toolkit/screens/tool_view/module_uri_resolver.dart'
    as uri_resolver;
import 'package:neuro_toolkit/screens/tool_view/module_webview_surface.dart';
import 'package:neuro_toolkit/screens/tool_view/tool_view_workspace_controller.dart';

Widget buildLoadingState(WidgetRef ref, Module module) {
  return ModuleLoadingView(
    module: module,
    healthCheckUri: uri_resolver.moduleUri(ref, module, healthCheck: true),
  );
}

/// Builds the active embedded surface for a module.
///
/// Shared by the desktop [Scaffold] and narrow [NmtkMobileScaffold] paths.
/// Both paths intentionally mount only their active module: native module
/// trees and WebViews must be disposed when a user switches away instead of
/// accumulating hidden frontends in memory.
Widget buildModuleChild(
  BuildContext context,
  WidgetRef ref,
  ToolViewWorkspaceController workspace,
  Module module,
  Map<String, WorkspaceSession> sessionsByModuleId, {
  Widget? workspaceHeaderAction,
}) {
  final session = sessionsByModuleId[module.id];
  final loadFailure = workspace.moduleLoadFailures[module.id];
  final supported = isWebViewSupported();
  final launchBlocked =
      module.isPreflightFailed || module.status == ModuleStatus.error;
  final isReady =
      module.status == ModuleStatus.running ||
      module.status == ModuleStatus.degraded;

  // SelectionContainer.disabled: the module workspace (canvases, steppers,
  // buttons) must not inherit the app-wide SelectionArea from LauncherAppHost —
  // Scrollable's text-selection-drag autoscroll trips Flutter's "Drag
  // target size is larger than scrollable size" assert on any short/thin
  // scrollable in that subtree, causing bounce/jank on first press or drag.
  return SelectionContainer.disabled(
    child: KeyedSubtree(
      key: ValueKey(module.id),
      child: launchBlocked
          ? NmtkEmptyState(
              title: '${module.name} Could Not Start',
              message: [
                module.statusMessage ?? 'This module could not be started.',
                if (module.capabilityWarnings.isNotEmpty)
                  module.capabilityWarnings.join('\n'),
              ].join('\n\n'),
              icon: ZetaIcons.error_outline,
              tone: NmtkTone.danger,
              action: ConnectionErrorActions(
                onRetry: () =>
                    workspace.activateModule(module.id, requestFocus: false),
                retryLabel: 'Retry Start',
                // Every module depends on the same one launcher server —
                // "change server" always means reconnecting the whole app,
                // never a per-module override.
                onChangeServer: () => showServerConnectionPopup(context, ref),
              ),
            )
          : session == null || !isReady
          ? buildLoadingState(ref, module)
          : loadFailure != null
          ? buildModuleLoadFailureState(
              context,
              ref,
              workspace,
              module,
              loadFailure,
            )
          : session.surfaceMode == 'native'
          ? NativeSurfaceRegistry.build(
              session,
              launchContext: NmtkFeatureLaunchContext(
                moduleId: NmtkModuleId.fromExternal(module.id),
                backendUri: Uri.parse(
                  uri_resolver.nativeSurfaceServerUrl(ref, module) ??
                      (throw StateError(
                        'The root launcher must supply a backend URL for ${module.id}.',
                      )),
                ),
                authentication: NmtkFeatureAuthentication(
                  adminToken: uri_resolver.tunnelSession(ref)?.adminToken ?? '',
                ),
                initialLocation:
                    session.deepLink ??
                    (module.id == 'Neurochip' ? '/?panel=deploy' : '/'),
                restorationState: session.restoreState,
                onNavigate: (request) => handleHostedModuleNavigationRequest(
                  ref,
                  workspace,
                  request,
                ),
                onReportError: (NmtkFeatureErrorEvent event) =>
                    reportHostedFeatureError(
                      context,
                      event,
                      onOpenBackendSetup: () =>
                          showServerConnectionPopup(context, ref),
                    ),
                onEditServer: () => showServerConnectionPopup(context, ref),
                workspaceHeaderAction: workspaceHeaderAction,
              ),
            )
          : supported
          ? buildModuleWebView(context, ref, workspace, module)
          : NmtkEmptyState(
              title: 'WebView Not Supported',
              message: '${module.name} cannot be displayed on this platform.',
              icon: ZetaIcons.warning_outline,
              tone: NmtkTone.warning,
            ),
    ),
  );
}
