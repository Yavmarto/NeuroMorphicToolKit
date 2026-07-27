import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';

part 'launcher_bootstrap_notifier.g.dart';

typedef LauncherBootstrapProbe =
    Future<LauncherBootstrapState> Function(Uri baseUri);

typedef LauncherControlApiFactory = ControlApiService Function(Uri baseUri);
typedef LauncherSelectionSaver =
    Future<void> Function(Uri launcherBaseUri, Uri? suiteBaseUri);

final launcherBootstrapProbeProvider = Provider<LauncherBootstrapProbe>((ref) {
  return (baseUri) => LauncherControlBootstrapService(
    explicitBaseUriOverride: baseUri,
  ).ensureReady();
});

final launcherControlApiFactoryProvider = Provider<LauncherControlApiFactory>((
  ref,
) {
  return (baseUri) => ControlApiService(
    baseUri: baseUri,
    analyticsService: ref.read(analyticsServiceProvider),
  );
});

final launcherSelectionSaverProvider = Provider<LauncherSelectionSaver>((ref) {
  return (launcherBaseUri, suiteBaseUri) async {
    final settings = ref.read(settingsProvider.notifier);
    await settings.setLauncherControlApiBaseUrl(launcherBaseUri.toString());
    await settings.setSuiteApiBaseUrl(suiteBaseUri?.toString());
  };
});

/// Drives the pre-app bootstrap flow: probing the launcher control API, loading
/// launcher settings, and surfacing the combined result to the widget tree.
///
/// `keepAlive: true` because this provider owns the one-time bootstrap sequence
/// and must not reset during the transition from setup to the workspace.
@Riverpod(keepAlive: true)
class LauncherBootstrapNotifier extends _$LauncherBootstrapNotifier {
  @override
  Future<LauncherBootstrapData> build() async {
    // Defer actual bootstrap; start in the loading state so the host widget
    // can immediately render the loading view without a manual trigger.
    return _runBootstrap();
  }

  Future<String?> connectToLauncher(String rawInput) {
    return _connect(rawInput);
  }

  Future<void> connectToDeploymentTarget(DeploymentTarget target) async {
    await _connect(target.host, deployedTarget: target);
  }

  /// Records a navigation failure after the launcher has already been
  /// verified. This is deliberately non-fatal: the selected service remains
  /// usable in memory and the user can retry the route handoff.
  Future<void> recordRouteHandoffFailure(Object error) {
    return _recordFailure(
      'route_handoff',
      error,
      state.value?.bootstrapState?.baseUri,
    );
  }

  Future<String?> _connect(
    String rawInput, {
    DeploymentTarget? deployedTarget,
  }) async {
    late final Uri candidateBaseUri;
    try {
      candidateBaseUri = ControlApiService.normalizeBaseUri(rawInput);
    } on FormatException catch (error) {
      final result = LauncherBootstrapData.needsSetup(
        message: error.message.toString(),
      );
      state = AsyncData(result);
      return result.setupMessage;
    }

    // Keep the current setup form mounted while the field shows its local
    // Connecting state. Replacing the provider value with AsyncLoading here
    // used to discard the user's input and produced the visible flicker.
    final result = await _runBootstrap(
      explicitBaseUriOverride: candidateBaseUri,
    );

    if (!result.isReady) {
      state = AsyncData(result);
      return result.setupMessage;
    }

    final verifiedTarget =
        result.launcherSettings?.selectedBackendDeploymentTarget;
    final suiteTarget = verifiedTarget ?? deployedTarget;
    Uri? suiteUri;
    if (suiteTarget != null) {
      final suiteHost = suiteTarget.host.trim().isEmpty
          ? candidateBaseUri.host
          : suiteTarget.host.trim();
      suiteUri = Uri(
        scheme: candidateBaseUri.scheme,
        host: suiteHost,
        port: suiteTarget.backendPort,
      );
    }

    // The verified service is authoritative for this app session. Enter the
    // workspace before persisting the convenience setting so storage trouble
    // can never turn a successful launcher connection back into setup.
    state = AsyncData(result);
    try {
      await ref.read(launcherSelectionSaverProvider)(
        candidateBaseUri,
        suiteUri,
      );
    } on Object catch (error) {
      await _recordFailure('persistence', error, candidateBaseUri);
    }
    return null;
  }

  Future<LauncherBootstrapData> _runBootstrap({
    Uri? explicitBaseUriOverride,
  }) async {
    Uri? explicitBaseUri = explicitBaseUriOverride;
    if (explicitBaseUri == null) {
      final settings = ref.read(settingsProvider).value;
      try {
        explicitBaseUri = _configuredBaseUri(
          settings?.launcherControlApiBaseUrl,
        );
      } on FormatException catch (error) {
        await _recordFailure('address', error, null);
        return LauncherBootstrapData.needsSetup(
          message: error.message.toString(),
        );
      }
    }

    if (explicitBaseUri == null) {
      return LauncherBootstrapData.needsSetup(
        message: 'Choose a launcher server before opening the workspace.',
      );
    }

    late final LauncherBootstrapState bootstrap;
    try {
      bootstrap = await ref.read(launcherBootstrapProbeProvider)(
        explicitBaseUri,
      );
    } on Object catch (error) {
      await _recordFailure('health', error, explicitBaseUri);
      return LauncherBootstrapData.needsSetup(
        message: _connectionFailureMessage(error),
      );
    }

    if (!bootstrap.canUseControlApi) {
      // Preserve the reachable runtime service for diagnostics, while routing
      // recovery through the client-owned deployment flow.
      if (bootstrap.controlApiReachable) {
        return LauncherBootstrapData.needsSetup(
          bootstrapState: bootstrap,
          controlApiService: ref.read(launcherControlApiFactoryProvider)(
            bootstrap.baseUri!,
          ),
          message: bootstrap.message,
        );
      }
      return LauncherBootstrapData.needsSetup(message: bootstrap.message);
    }

    final controlApiService = ref.read(launcherControlApiFactoryProvider)(
      bootstrap.baseUri!,
    );

    try {
      final launcherSettings = await controlApiService.fetchSettings();
      if (launcherSettings.backendDeploymentReady) {
        return LauncherBootstrapData.ready(
          bootstrapState: bootstrap,
          controlApiService: controlApiService,
          launcherSettings: launcherSettings,
        );
      } else {
        return LauncherBootstrapData.needsSetup(
          bootstrapState: bootstrap,
          controlApiService: controlApiService,
          message:
              'This backend is not ready. Repair it or deploy another backend.',
        );
      }
    } on Object catch (error) {
      await _recordFailure('settings', error, explicitBaseUri);
      return LauncherBootstrapData.needsSetup(
        message: _settingsFailureMessage(error),
      );
    }
  }

  Uri? _configuredBaseUri(String? stored) {
    final configured = ControlApiService.configuredBaseUrl.trim();
    if (configured.isNotEmpty) {
      return ControlApiService.normalizeBaseUri(configured);
    }
    stored = stored?.trim() ?? '';
    if (stored.isNotEmpty) {
      return ControlApiService.normalizeBaseUri(stored);
    }
    return null;
  }

  Future<void> _recordFailure(String stage, Object error, Uri? baseUri) async {
    await ref
        .read(analyticsServiceProvider)
        .recordBackendActivity(
          method: 'BOOTSTRAP',
          uri: baseUri ?? Uri.parse('launcher://bootstrap'),
          error: 'stage=$stage category=${_failureCategory(error)}',
        );
  }

  String _failureCategory(Object error) {
    if (error is FormatException) {
      return 'invalid_response';
    }
    if (error is TimeoutException) {
      return 'timeout';
    }
    if (error is SocketException) {
      return 'unreachable';
    }
    return 'unexpected';
  }

  String _connectionFailureMessage(Object error) {
    return switch (_failureCategory(error)) {
      'timeout' =>
        'Connection timed out. Confirm this device can reach the launcher '
            'host, then try again.',
      'unreachable' =>
        'The launcher host could not be reached. Confirm the address and that '
            'the launcher service is running, then try again.',
      _ =>
        'Preflight failed while checking this launcher host. Confirm the '
            'address and try again.',
    };
  }

  String _settingsFailureMessage(Object error) {
    return switch (_failureCategory(error)) {
      'timeout' =>
        'The launcher answered, but loading its settings timed out. Try again.',
      'invalid_response' =>
        'The launcher answered with settings this app could not read. Update '
            'the launcher service and try again.',
      _ =>
        'Preflight failed while loading settings from this launcher host. '
            'Confirm the launcher service is healthy, then try again.',
    };
  }
}
