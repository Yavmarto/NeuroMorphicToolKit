import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';

part 'launcher_bootstrap_notifier.g.dart';

/// Drives the pre-app bootstrap flow: probing the launcher control API, loading
/// launcher settings, and surfacing the combined result to the widget tree.
///
/// Replaces all [setState] calls in [_LauncherBootstrapHostState] in main.dart.
///
/// `keepAlive: true` because this provider owns the one-time bootstrap sequence
/// and must not reset when the widget temporarily unmounts during the transition
/// from the setup flow to the main app shell.
@Riverpod(keepAlive: true)
class LauncherBootstrapNotifier extends _$LauncherBootstrapNotifier {
  @override
  Future<LauncherBootstrapData> build() async {
    // Defer actual bootstrap; start in the loading state so the host widget
    // can immediately render the loading view without a manual trigger.
    return _runBootstrap();
  }

  /// Normalises a raw host/URL input entered by the user and stores it in
  /// settings, then reruns the bootstrap probe.
  Future<void> saveAndRetry(String rawInput) async {
    await ref
        .read(settingsProvider.notifier)
        .setLauncherControlApiBaseUrl(rawInput);
    state = const AsyncLoading();
    state = await AsyncValue.guard(_runBootstrap);
  }

  Future<LauncherBootstrapData> _runBootstrap() async {
    final settings = ref.read(settingsProvider).value;
    final isMobile = _isMobilePlatform();

    final explicitBaseUri =
        _configuredBaseUri(settings?.launcherControlApiBaseUrl);

    if (isMobile && explicitBaseUri == null) {
      return LauncherBootstrapData.needsSetup(
        message:
            'Set the launcher control API host before opening the workspace.',
      );
    }

    final bootstrap = await LauncherControlBootstrapService(
      explicitBaseUriOverride: explicitBaseUri,
    ).ensureReady();

    if (!bootstrap.canUseControlApi) {
      return LauncherBootstrapData.needsSetup(
        message: bootstrap.message,
      );
    }

    final controlApiService = ControlApiService(
      baseUri: bootstrap.baseUri,
      analyticsService: ref.read(analyticsServiceProvider),
    );

    try {
      final launcherSettings = await controlApiService.fetchSettings();
      if (launcherSettings.backendDeploymentReady) {
        return LauncherBootstrapData.ready(
          bootstrapState: bootstrap,
          controlApiService: controlApiService,
        );
      } else {
        return LauncherBootstrapData.needsSetup(
          bootstrapState: bootstrap,
          controlApiService: controlApiService,
          message:
              'Connect to another launcher server or set up a new one here.',
        );
      }
    } catch (_) {
      return LauncherBootstrapData.needsSetup(
        message: 'Preflight failed: could not load settings from this '
            'launcher host. Confirm the launcher control API is running and '
            'reachable, then try again.',
      );
    }
  }

  Uri? _configuredBaseUri(String? stored) {
    final configured = ControlApiService.configuredBaseUrl.trim();
    if (configured.isNotEmpty) return Uri.parse(configured);
    stored = stored?.trim() ?? '';
    if (stored.isNotEmpty) return Uri.parse(stored);
    return null;
  }

  static bool _isMobilePlatform() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
