import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/cross_module_navigation.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/screens/tool_view/module_uri_resolver.dart'
    as uri_resolver;
import 'package:neuro_toolkit/screens/tool_view/tool_view_workspace_controller.dart';

/// Sends the user back to the connect screen for a new server pick.
///
/// Logs out of the current Connect session, which flips
/// `connectNotifierProvider` to `idle`; `ServerAccessGate` (mounted above
/// `LauncherAppHost`) reacts by swapping in `ServerConnectScreen`.
Future<void> showServerConnectionPopup(BuildContext context, WidgetRef ref) {
  ref.read(connectNotifierProvider.notifier).logout();
  return Future<void>.value();
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
    await showServerConnectionPopup(context, ref);
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

// Every failed request from the embedded module reports its own error, so a
// dead backend can trigger this many times a second. Connection/auth errors go
// to the app-wide top-right notification stack, which coalesces repeat reports
// for the same module+kind into a single card. The remaining kinds still use a
// bottom SnackBar; this flag keeps that fallback from re-queuing a fresh
// SnackBar per failure while one is already on screen.
bool _hostedFeatureErrorSnackBarVisible = false;

bool _requiresBackendSetup(NmtkFeatureErrorKind kind) {
  return kind == NmtkFeatureErrorKind.connection ||
      kind == NmtkFeatureErrorKind.authentication;
}

String _hostedFeatureErrorTitle(NmtkFeatureErrorKind kind) {
  return switch (kind) {
    NmtkFeatureErrorKind.connection => 'Connection Problem',
    NmtkFeatureErrorKind.authentication => 'Authentication Problem',
    NmtkFeatureErrorKind.navigation ||
    NmtkFeatureErrorKind.unexpected => 'NeuroStudio Problem',
  };
}

IconData _hostedFeatureErrorIcon(NmtkFeatureErrorKind kind) {
  return switch (kind) {
    NmtkFeatureErrorKind.connection => ZetaIcons.cloud_off,
    NmtkFeatureErrorKind.authentication => ZetaIcons.error_outline,
    NmtkFeatureErrorKind.navigation ||
    NmtkFeatureErrorKind.unexpected => ZetaIcons.error_outline,
  };
}

Future<void> reportHostedFeatureError(
  BuildContext context,
  NmtkFeatureErrorEvent event, {
  required VoidCallback onOpenBackendSetup,
}) async {
  if (!context.mounted) return;
  final requiresBackendSetup = _requiresBackendSetup(event.kind);

  // Connection/auth failures read as macOS-style banners in the top-right
  // corner (see CEL-117): rounded card, icon, title/message and the same
  // "Backend Setup" action as the previous bottom SnackBar. The key coalesces
  // the per-request reports a dead backend produces, so only one card is live.
  if (requiresBackendSetup) {
    final notificationCenter = NmtkNotificationCenter.maybeControllerOf(
      context,
    );
    if (notificationCenter != null) {
      notificationCenter.push(
        NmtkNotification(
          key: 'hosted-feature-error:${event.kind}',
          title: _hostedFeatureErrorTitle(event.kind),
          message: event.message,
          tone: NmtkTone.danger,
          icon: _hostedFeatureErrorIcon(event.kind),
          // Persistent until the user opens Backend Setup or closes the card.
          duration: null,
          action: NmtkNotificationAction(
            label: 'Backend Setup',
            onPressed: onOpenBackendSetup,
          ),
        ),
      );
      return;
    }
  }

  // Non-connection failures (navigation/unexpected) keep the bottom SnackBar.
  // This is also the fallback when no notification host is mounted above
  // [context] (e.g. in a bare widget-test harness).
  if (_hostedFeatureErrorSnackBarVisible) return;
  _hostedFeatureErrorSnackBarVisible = true;
  unawaited(
    ScaffoldMessenger.of(context)
        .showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(event.message),
            duration: const Duration(days: 1),
            showCloseIcon: true,
            action: requiresBackendSetup
                ? SnackBarAction(
                    label: 'Backend Setup',
                    onPressed: onOpenBackendSetup,
                  )
                : null,
          ),
        )
        .closed
        .then((_) => _hostedFeatureErrorSnackBarVisible = false),
  );
}
