import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/src/features/launcher_bootstrap/presentation/launcher_bootstrap_notifier.dart';

enum ServerConnectionPhase {
  checking,
  connected,
  unstable,
  disconnected,
}

class ServerConnectionState {
  const ServerConnectionState({
    required this.phase,
    required this.baseUri,
    this.consecutiveFailures = 0,
    this.lastCheckedAt,
  });

  const ServerConnectionState.disconnected()
      : phase = ServerConnectionPhase.disconnected,
        baseUri = null,
        consecutiveFailures = 0,
        lastCheckedAt = null;

  final ServerConnectionPhase phase;
  final Uri? baseUri;
  final int consecutiveFailures;
  final DateTime? lastCheckedAt;

  String get label => switch (phase) {
        ServerConnectionPhase.checking => 'Checking',
        ServerConnectionPhase.connected => 'Connected',
        ServerConnectionPhase.unstable => 'Connection unstable',
        ServerConnectionPhase.disconnected => 'Disconnected',
      };
}

typedef ServerHealthProbe = Future<bool> Function(
  ControlApiService controlApi,
);

final serverHealthProbeProvider = Provider<ServerHealthProbe>((ref) {
  return (controlApi) => controlApi.isAvailable(
        timeout: const Duration(seconds: 2),
      );
});

/// Tracks liveness for exactly one launcher URI at a time.
///
/// Every activation increments [_generation]. A response from an earlier
/// generation is ignored, so a slow request to server A can never publish
/// health for server B after the user switches.
class ServerConnectionNotifier extends Notifier<ServerConnectionState> {
  static const checkInterval = Duration(seconds: 5);
  static const failuresBeforeDisconnect = 3;

  Timer? _timer;
  AppLifecycleListener? _lifecycleListener;
  ControlApiService? _activeControlApi;
  Uri? _activeBaseUri;
  int _generation = 0;
  int? _probeInFlightGeneration;
  bool _disposeRegistered = false;

  @override
  ServerConnectionState build() {
    final bootstrap = ref.watch(launcherBootstrapProvider).value;
    final controlApi =
        bootstrap?.isReady == true ? bootstrap?.controlApiService : null;
    final baseUri = controlApi?.baseUri;

    if (!_disposeRegistered) {
      _disposeRegistered = true;
      _lifecycleListener = AppLifecycleListener(
        onResume: () => unawaited(checkNow()),
      );
      ref.onDispose(() {
        _timer?.cancel();
        _lifecycleListener?.dispose();
      });
    }

    if (controlApi == null || baseUri == null) {
      _activate(null);
      return const ServerConnectionState.disconnected();
    }

    if (_activeBaseUri != baseUri) {
      _activate(controlApi);
    } else {
      _activeControlApi = controlApi;
    }

    final generation = _generation;
    Future<void>.microtask(() => _probe(generation));
    return ServerConnectionState(
      phase: ServerConnectionPhase.checking,
      baseUri: baseUri,
    );
  }

  Future<void> checkNow() => _probe(_generation);

  void _activate(ControlApiService? controlApi) {
    _timer?.cancel();
    _generation++;
    _probeInFlightGeneration = null;
    _activeControlApi = controlApi;
    _activeBaseUri = controlApi?.baseUri;

    if (controlApi == null) {
      return;
    }

    _timer = Timer.periodic(checkInterval, (_) {
      unawaited(_probe(_generation));
    });
  }

  Future<void> _probe(int generation) async {
    final controlApi = _activeControlApi;
    final baseUri = _activeBaseUri;
    if (controlApi == null ||
        baseUri == null ||
        generation != _generation ||
        _probeInFlightGeneration == generation) {
      return;
    }

    _probeInFlightGeneration = generation;
    var connected = false;
    try {
      connected = await ref.read(serverHealthProbeProvider)(controlApi);
    } on Object {
      connected = false;
    } finally {
      if (_probeInFlightGeneration == generation) {
        _probeInFlightGeneration = null;
      }
    }

    if (generation != _generation || baseUri != _activeBaseUri) {
      return;
    }

    final checkedAt = DateTime.now();
    if (connected) {
      state = ServerConnectionState(
        phase: ServerConnectionPhase.connected,
        baseUri: baseUri,
        lastCheckedAt: checkedAt,
      );
      return;
    }

    final previousFailures =
        state.baseUri == baseUri ? state.consecutiveFailures : 0;
    final failures = previousFailures + 1;
    state = ServerConnectionState(
      phase: failures >= failuresBeforeDisconnect
          ? ServerConnectionPhase.disconnected
          : ServerConnectionPhase.unstable,
      baseUri: baseUri,
      consecutiveFailures: failures,
      lastCheckedAt: checkedAt,
    );
  }
}

final serverConnectionProvider =
    NotifierProvider<ServerConnectionNotifier, ServerConnectionState>(
  ServerConnectionNotifier.new,
);
