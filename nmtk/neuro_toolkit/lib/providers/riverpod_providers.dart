import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/backend_tunnel_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/deployment/client_deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/environment_api_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';
import 'package:neuro_toolkit/services/update_service.dart';

// Re-export generated Riverpod providers for convenience
export 'package:neuro_toolkit/src/features/app/presentation/app_notifier.dart'
    show appProvider;
export 'package:neuro_toolkit/src/features/module/presentation/module_notifier.dart'
    show moduleProvider;
export 'package:neuro_toolkit/src/features/server_connection/presentation/server_connection_notifier.dart'
    show ServerConnectionPhase, ServerConnectionState, serverConnectionProvider;
export 'package:neuro_toolkit/src/features/workspace/presentation/workspace_notifier.dart'
    show workspaceProvider;
export 'package:neuro_toolkit/src/features/settings/presentation/settings_notifier.dart'
    show settingsProvider;
export 'package:neuro_toolkit/src/features/environment/presentation/environment_notifier.dart'
    show environmentProvider;
export 'package:neuro_toolkit/src/features/environment/presentation/environment_package_notifier.dart'
    show
        environmentPackageProvider,
        environmentExportProvider,
        EnvironmentPackageNotifier,
        EnvironmentExportNotifier;
export 'package:neuro_toolkit/src/features/environment/domain/environment_package_state.dart'
    show EnvironmentPackageState, EnvironmentExportState;
export 'package:neuro_toolkit/src/features/deployment/presentation/deployment_notifier.dart'
    show backendDeploymentProvider;
export 'package:neuro_toolkit/src/features/python_install/presentation/python_install_notifier.dart'
    show pythonInstallProvider, PythonInstallNotifier;
export 'package:neuro_toolkit/src/features/python_install/domain/python_install_state.dart'
    show PythonInstallState;

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  throw UnimplementedError(
    'analyticsServiceProvider must be overridden at app bootstrap.',
  );
});

final deploymentServiceProvider = Provider<DeploymentService>((ref) {
  return ClientDeploymentService();
});

final backendTunnelServiceProvider = Provider<BackendTunnelService>((ref) {
  final service = BackendTunnelService();
  ref.onDispose(service.close);
  return service;
});

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

/// The currently resolved launcher service, sourced from the Connect
/// session (see `features/server/connect/connect_notifier.dart`) rather than
/// the old SSH/admin-token bootstrap flow. Presentation code uses this
/// nullable provider so the normal app shell can remain mounted before a
/// server is connected. Operations that require a launcher should continue
/// to use [controlApiServiceProvider].
final selectedControlApiServiceProvider = Provider<ControlApiService?>((ref) {
  final state = ref.watch(connectNotifierProvider);
  final session = state.session;
  if (state.phase != ConnectPhase.connected || session == null) {
    return null;
  }
  return ControlApiService(
    baseUri: ControlApiService.normalizeBaseUri(session.host),
    adminToken: session.sessionToken,
    analyticsService: ref.read(analyticsServiceProvider),
  );
});

/// Bridges the Connect session into the [LauncherBootstrapState] shape that
/// `ModuleNotifier`/`WorkspaceNotifier` still gate on. There is no longer a
/// separate bootstrap phase — a connected session is immediately "ready".
final launcherBootstrapStateProvider = Provider<LauncherBootstrapState>((ref) {
  final controlApi = ref.watch(selectedControlApiServiceProvider);
  if (controlApi == null) {
    return LauncherBootstrapState.noServerSelected();
  }
  return LauncherBootstrapState.ready(controlApi.baseUri);
});

/// Whether the neurocnl module's own backend (its `/health` probe, distinct
/// from the launcher control-API ping) is degraded or unreachable. NeuroStudio
/// writes to this so the top-right connection dot can reflect it without a
/// second poll loop.
class NeurocnlBackendDegradedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final neurocnlBackendDegradedProvider =
    NotifierProvider<NeurocnlBackendDegradedNotifier, bool>(
      NeurocnlBackendDegradedNotifier.new,
    );

final controlApiServiceProvider = Provider<ControlApiService>((ref) {
  final controlApiService = ref.watch(selectedControlApiServiceProvider);
  if (controlApiService == null) {
    throw StateError('No launcher server has been selected.');
  }
  return controlApiService;
});

final environmentApiServiceProvider = Provider<EnvironmentApiService>((ref) {
  return EnvironmentApiService(
    controlApi: ref.watch(controlApiServiceProvider),
  );
});

/// The release identifier reported by the connected backend.
///
/// `"dev"` means a source build. Null means there is no selected launcher, the
/// backend is unreachable, or the backend predates version reporting.
final backendVersionProvider = FutureProvider<String?>((ref) async {
  final ControlApiService controlApi;
  try {
    controlApi = ref.watch(controlApiServiceProvider);
  } on StateError {
    return null;
  }
  return controlApi.fetchBackendVersion();
});

/// Whether the connected backend is behind the newest published release.
///
/// Null when there is nothing to offer: no launcher selected, the backend is
/// unreachable or too old to report a version, it was built from source
/// (`"dev"`), GitHub is unreachable, or it is already current. Callers show an
/// update affordance only for a non-null value, so every failure mode
/// degrades to "say nothing" rather than to a false prompt.
final backendUpdateProvider = FutureProvider<LauncherUpdate?>((ref) async {
  final running = await ref.watch(backendVersionProvider.future);
  if (running == null) {
    return null;
  }
  return ref.watch(updateServiceProvider).checkForBackendUpdate(running);
});

/// Selected Akida host release status, kept independent from core backend
/// update availability so a failed optional runtime remains recoverable after
/// the suite itself is current.
final selectedAkidaRuntimeStatusProvider = FutureProvider<AkidaPairedHost?>((
  ref,
) async {
  final controlApi = ref.watch(selectedControlApiServiceProvider);
  if (controlApi == null) return null;
  try {
    return (await controlApi.fetchSettings()).selectedAkidaHost;
  } on Object {
    return null;
  }
});

// The Teensy / PYNQ / Akida deploy providers were relocated to the Neurochip
// module frontend in ADR-claude/0007. They now live in
// `Neurochip/frontend/lib/providers/riverpod_providers.dart`.
