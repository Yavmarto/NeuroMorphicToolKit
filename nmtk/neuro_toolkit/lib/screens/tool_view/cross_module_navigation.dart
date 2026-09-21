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
import 'package:neuro_toolkit/screens/server_access_popup.dart';
import 'package:neuro_toolkit/screens/tool_view/tool_view_workspace_controller.dart';

/// Opens the server popup for the current session, or the sign-in flow when
/// disconnected.
///
/// When already connected, the popup shows live server stats without logging
/// out. "Change server" inside the popup signs out and returns to sign-in.
Future<void> showServerConnectionPopup(BuildContext context, WidgetRef ref) {
  final phase = ref.read(connectNotifierProvider).phase;
  if (phase == ConnectPhase.connected || phase == ConnectPhase.devOffline) {
    return showServerAccessPopup(context);
  }
  ref.read(connectNotifierProvider.notifier).logout();
  ref.read(serverAccessPopupRequestProvider.notifier).request();
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
// dead backend can trigger this many times a second. All kinds go to the
// app-wide top-right notification stack, which coalesces repeat reports for
// the same kind into a single card.
// requests (see the report comment above), so connection/auth reports are
// queued for a short grace window before they become a persistent banner. A
// recovery signal during the window cancels the queued card entirely; only a
// backend that is still failing when the window expires promotes the card.
// Once promoted, later reports refresh it in place until a recovery dismisses
// it. This keeps a transient startup failure from leaving a permanent-looking
// "cannot reach backend" card after the connection recovers (CEL-129).
const Duration hostedFeatureErrorStartupGrace = Duration(seconds: 5);

/// Grace-suppressed connection/auth cards, keyed by kind. The banner key is
/// `hosted-feature-error:$kind` and is shared by every module, so a single
/// pending slot per kind is sufficient regardless of which module reported it.
final Map<NmtkFeatureErrorKind, ({String message, Timer timer})>
_pendingHostedFeatureErrors =
    <NmtkFeatureErrorKind, ({String message, Timer timer})>{};

/// Kinds whose banner is already live (promoted past the grace window) and so
/// refresh immediately on repeat reports.
final Set<NmtkFeatureErrorKind> _liveHostedFeatureErrorBanners =
    <NmtkFeatureErrorKind>{};

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

/// Promotes/replaces the live connection/auth banner for [kind] with [message].
void _pushHostedFeatureBanner(
  NmtkNotificationCenterController notificationCenter,
  NmtkFeatureErrorKind kind,
  String message,
  VoidCallback onOpenBackendSetup,
) {
  notificationCenter.push(
    NmtkNotification(
      key: 'hosted-feature-error:$kind',
      title: _hostedFeatureErrorTitle(kind),
      message: message,
      tone: NmtkTone.danger,
      icon: _hostedFeatureErrorIcon(kind),
      // Persistent until the user opens Backend Setup, closes the card, or a
      // later request succeeds (which dismisses it via clearHostedFeatureError).
      duration: null,
      action: NmtkNotificationAction(
        label: 'Backend Setup',
        onPressed: onOpenBackendSetup,
      ),
    ),
  );
}

/// Clears a stale "cannot reach backend" card once the embedded module proves
/// the backend is reachable again (a later request succeeded).
///
/// Cancels any connection/auth banner still queued inside the startup grace
/// window and dismisses any that are already visible. Wired to
/// `NmtkFeatureLaunchContext.onRecovered` by [buildModuleChild].
Future<void> clearHostedFeatureError(BuildContext context) async {
  if (!context.mounted) return;
  final notificationCenter = NmtkNotificationCenter.maybeControllerOf(context);
  if (notificationCenter == null) return;

  for (final entry in _pendingHostedFeatureErrors.values.toList()) {
    entry.timer.cancel();
  }
  _pendingHostedFeatureErrors.clear();
  _liveHostedFeatureErrorBanners.clear();
  for (final kind in const <NmtkFeatureErrorKind>[
    NmtkFeatureErrorKind.connection,
    NmtkFeatureErrorKind.authentication,
  ]) {
    notificationCenter.dismiss('hosted-feature-error:$kind');
  }
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
      final pending = _pendingHostedFeatureErrors[event.kind];
      if (pending != null) {
        // Still inside the startup grace window: refresh the queued message
        // but keep the card suppressed (a recovery may still arrive).
        _pendingHostedFeatureErrors[event.kind] = (
          message: event.message,
          timer: pending.timer,
        );
        return;
      }
      if (_liveHostedFeatureErrorBanners.contains(event.kind)) {
        // Already promoted past the grace window: refresh in place.
        _pushHostedFeatureBanner(
          notificationCenter,
          event.kind,
          event.message,
          onOpenBackendSetup,
        );
        return;
      }
      // First report for this kind: queue it. If the backend has not recovered
      // by the time the grace window expires, promote it to a real card; a
      // recovery signal in between cancels it.
      final timer = Timer(hostedFeatureErrorStartupGrace, () {
        final latestMessage =
            _pendingHostedFeatureErrors[event.kind]?.message ?? event.message;
        _pendingHostedFeatureErrors.remove(event.kind);
        _liveHostedFeatureErrorBanners.add(event.kind);
        _pushHostedFeatureBanner(
          notificationCenter,
          event.kind,
          latestMessage,
          onOpenBackendSetup,
        );
      });
      _pendingHostedFeatureErrors[event.kind] = (
        message: event.message,
        timer: timer,
      );
      return;
    }
  }

  // Non-connection failures show immediately as top-right banners. When no
  // notification host is mounted above [context] (e.g. a bare widget-test
  // harness), this is a no-op.
  final notificationCenter = NmtkNotificationCenter.maybeControllerOf(context);
  if (notificationCenter == null) return;

  notificationCenter.push(
    NmtkNotification(
      key: 'hosted-feature-error:${event.kind}',
      title: _hostedFeatureErrorTitle(event.kind),
      message: event.message,
      tone: NmtkTone.danger,
      icon: _hostedFeatureErrorIcon(event.kind),
      duration: const Duration(seconds: 6),
    ),
  );
}
