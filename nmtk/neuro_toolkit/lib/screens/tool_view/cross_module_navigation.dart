import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/cross_module_navigation.dart';
import 'package:neuro_toolkit/widgets/server_setup_popup.dart';

import 'package:neuro_toolkit/screens/tool_view/module_uri_resolver.dart'
    as uri_resolver;
import 'package:neuro_toolkit/screens/tool_view/tool_view_workspace_controller.dart';

Future<void> showServerConnectionPopup(BuildContext context, WidgetRef ref) {
  return showAdaptiveServerSetupPopup(
    context,
    initialHost: uri_resolver.launcherBaseUri(ref)?.toString(),
  );
}

Future<bool> handleCrossModuleNavigation(
  BuildContext context,
  WidgetRef ref,
  ToolViewWorkspaceController workspace,
  Module currentModule,
  Uri requestUri,
) async {
  if (!context.mounted) return false;
  if (requestUri.scheme == 'nmtk' && requestUri.host == 'system-health') {
    await showAdaptiveServerSetupPopup(
      context,
      message:
          'System Health checks the backend, storage, Jupyter, '
          'snnTorch, launcher control, and configured hardware.',
    );
    return true;
  }
  final moduleState = ref.read(moduleProvider).value;
  if (moduleState == null) return false;

  final navigation = resolveCrossModuleNavigation(
    targetUri: requestUri,
    modules: moduleState.modules,
    currentModuleId: currentModule.id,
  );
  if (navigation == null) {
    return false;
  }

  final targetModule = navigation.targetModule;
  workspace.pendingModuleRequests[targetModule.id] = navigation.targetUri;

  await ref
      .read(workspaceProvider.notifier)
      .openSession(
        targetModule.id,
        surfaceMode: uri_resolver.surfaceModeForModule(targetModule.id),
        deepLink: launcherDeepLinkFromUri(navigation.targetUri),
        readinessState: 'opening',
      );
  if (!context.mounted) return false;

  if (workspace.controllers.containsKey(targetModule.id)) {
    workspace.pendingModuleRequests.remove(targetModule.id);
    await workspace.controllers[targetModule.id]!.loadUrl(
      urlRequest: URLRequest(url: WebUri.uri(navigation.targetUri)),
    );
    if (!context.mounted) return false;
  }

  await workspace.activateModule(targetModule.id, requestFocus: true);
  return true;
}

Future<bool> handleHostedModuleNavigationRequest(
  WidgetRef ref,
  ToolViewWorkspaceController workspace,
  NmtkFeatureNavigationRequest request,
) async {
  if (!workspace.mounted) return false;
  final moduleState = ref.read(moduleProvider).value;
  final workspaceState = ref.read(workspaceProvider).value;
  if (moduleState == null || workspaceState == null) return false;

  final targetModule = moduleState.modules
      .where(
        (Module module) =>
            NmtkModuleId.fromExternal(module.id) == request.moduleId,
      )
      .cast<Module?>()
      .firstWhere((Module? module) => module != null, orElse: () => null);
  if (targetModule == null || !workspace.shouldOpenModule(targetModule)) {
    return false;
  }

  final existingSession = workspaceState.sessions
      .where((WorkspaceSession session) => session.moduleId == targetModule.id)
      .cast<WorkspaceSession?>()
      .firstWhere(
        (WorkspaceSession? session) => session != null,
        orElse: () => null,
      );
  final restoreState = Map<String, dynamic>.from(request.restorationState);
  final readinessState = workspace.readinessStateForModule(targetModule);

  if (existingSession == null) {
    await ref
        .read(workspaceProvider.notifier)
        .openSession(
          targetModule.id,
          surfaceMode: uri_resolver.surfaceModeForModule(targetModule.id),
          deepLink: request.deepLink,
          restoreState: restoreState,
          readinessState: readinessState,
        );
  } else {
    await ref
        .read(workspaceProvider.notifier)
        .updateSession(
          targetModule.id,
          deepLink: request.deepLink,
          restoreState: restoreState,
          readinessState: readinessState,
        );
  }

  await workspace.activateModule(targetModule.id, requestFocus: true);
  return true;
}

Future<void> reportHostedFeatureError(
  BuildContext context,
  NmtkFeatureErrorEvent event, {
  required VoidCallback onOpenBackendSetup,
}) async {
  if (!context.mounted) return;
  final requiresBackendSetup =
      event.kind == NmtkFeatureErrorKind.connection ||
      event.kind == NmtkFeatureErrorKind.authentication;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(event.message),
      action: requiresBackendSetup
          ? SnackBarAction(
              label: 'Backend Setup',
              onPressed: onOpenBackendSetup,
            )
          : null,
    ),
  );
}
