import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/models/system_resources.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart'
    show selectedControlApiServiceProvider;
import 'package:neuro_toolkit/services/control_api_service.dart';

class SystemResourcesState {
  const SystemResourcesState({
    this.snapshot,
    this.isLoading = true,
    this.lastUpdatedAt,
  });

  const SystemResourcesState.unavailable()
    : snapshot = null,
      isLoading = false,
      lastUpdatedAt = null;

  final SystemResourcesSnapshot? snapshot;
  final bool isLoading;
  final DateTime? lastUpdatedAt;
}

typedef SystemResourcesFetcher =
    Future<SystemResourcesSnapshot?> Function(ControlApiService controlApi);

final systemResourcesFetcherProvider = Provider<SystemResourcesFetcher>((ref) {
  return (controlApi) => controlApi.fetchSystemResources();
});

/// Polls `GET /api/suite/system/resources` while watched (e.g. server popup).
class SystemResourcesNotifier extends Notifier<SystemResourcesState> {
  static const pollInterval = Duration(seconds: 5);

  Timer? _timer;
  ControlApiService? _activeControlApi;
  int _generation = 0;
  int? _fetchInFlightGeneration;

  @override
  SystemResourcesState build() {
    final controlApi = ref.watch(selectedControlApiServiceProvider);

    ref.onDispose(() {
      _timer?.cancel();
    });

    if (controlApi == null) {
      _activate(null);
      return const SystemResourcesState.unavailable();
    }

    if (_activeControlApi?.baseUri != controlApi.baseUri) {
      _activate(controlApi);
    } else {
      _activeControlApi = controlApi;
    }

    final generation = _generation;
    Future<void>.microtask(() => _fetch(generation));
    return const SystemResourcesState(isLoading: true);
  }

  void _activate(ControlApiService? controlApi) {
    _timer?.cancel();
    _generation++;
    _fetchInFlightGeneration = null;
    _activeControlApi = controlApi;

    if (controlApi == null) {
      return;
    }

    _timer = Timer.periodic(pollInterval, (_) {
      unawaited(_fetch(_generation));
    });
  }

  Future<void> _fetch(int generation) async {
    final controlApi = _activeControlApi;
    if (controlApi == null ||
        generation != _generation ||
        _fetchInFlightGeneration == generation) {
      return;
    }

    _fetchInFlightGeneration = generation;
    SystemResourcesSnapshot? snapshot;
    try {
      snapshot = await ref.read(systemResourcesFetcherProvider)(controlApi);
    } on Object {
      snapshot = null;
    } finally {
      if (_fetchInFlightGeneration == generation) {
        _fetchInFlightGeneration = null;
      }
    }

    if (generation != _generation || controlApi != _activeControlApi) {
      return;
    }

    state = SystemResourcesState(
      snapshot: snapshot,
      isLoading: false,
      lastUpdatedAt: DateTime.now(),
    );
  }
}

final systemResourcesProvider =
    NotifierProvider.autoDispose<SystemResourcesNotifier, SystemResourcesState>(
      SystemResourcesNotifier.new,
    );
