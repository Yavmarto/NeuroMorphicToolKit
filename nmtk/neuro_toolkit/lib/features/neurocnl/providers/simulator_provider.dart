/// Riverpod providers for the simulator contract.
///
/// [simulatorCapabilitiesProvider] — AsyncNotifier that fetches backend
///   capability profiles from GET /api/simulators/capabilities.
///
/// [simulatorRunProvider] — StateNotifier that manages the current run state
///   (idle → running → result / error).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/simulator.dart';
import 'package:neuro_toolkit/features/neurocnl/models/trained_nir_artifact.dart';
import 'package:neuro_toolkit/features/neurocnl/services/simulator_service.dart';
import 'package:neuro_toolkit/features/neurocnl/services/admin_token_http_client.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/simulator_state.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/feature_launch_provider.dart';
export 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/simulator_state.dart';

part 'simulator_provider.g.dart';

// ---------------------------------------------------------------------------
// Service provider
// ---------------------------------------------------------------------------

final simulatorServiceProvider = Provider<SimulatorService>((ref) {
  final launchContext = ref.watch(featureLaunchContextProvider);
  return SimulatorService(
    baseUrl: launchContext.backendUri.toString(),
    httpClient: AdminTokenHttpClient(
      adminToken: launchContext.authentication.adminToken,
      onReportError: launchContext.onReportError,
      onRecovered: launchContext.onRecovered,
    ),
  );
});

// ---------------------------------------------------------------------------
// Capabilities provider
// ---------------------------------------------------------------------------

@riverpod
class SimulatorCapabilitiesController
    extends _$SimulatorCapabilitiesController {
  @override
  Future<List<SimulatorCapability>> build() async {
    final service = ref.watch(simulatorServiceProvider);
    try {
      return await service.getCapabilities();
    } catch (e) {
      debugPrint('SimulatorCapabilitiesController caught error: $e');
      rethrow;
    }
  }

  /// Refresh capabilities (e.g. after the user installs a dependency).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(simulatorServiceProvider).getCapabilities(),
    );
  }
}

/// Backward-compat alias.
final simulatorCapabilitiesProvider = simulatorCapabilitiesControllerProvider;

// ---------------------------------------------------------------------------
// Trained weights
// ---------------------------------------------------------------------------

/// The newest trained NIR graph in [workspaceFolder], or null when there is none.
///
/// Without it a run simulates the CNL spec's zeros — correct shapes, every value
/// 0.0, so no neuron can reach threshold and the raster comes back empty. This is
/// the same artifact the PYNQ deploy path reads, so a network trained once feeds
/// both.
///
/// A missing artifact is a null, not an error: "you have not trained this yet" is
/// a state the Run button reports, not a failure to surface.
@riverpod
Future<TrainedNirArtifact?> simulatorTrainedNir(
  Ref ref,
  String workspaceFolder,
) async {
  if (workspaceFolder.trim().isEmpty) return null;
  try {
    final json = await ref
        .read(apiClientProvider)
        .latestTrainedNir(workspaceFolder);
    final artifact = TrainedNirArtifact.fromJson(json);
    return artifact.isUsable ? artifact : null;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Run state
// ---------------------------------------------------------------------------

// Now imported from '../src/features/studio/domain/simulator_state.dart'

// ---------------------------------------------------------------------------
// Run provider
// ---------------------------------------------------------------------------

@riverpod
class SimulatorRunController extends _$SimulatorRunController {
  @override
  SimulatorRunState build(String backendName) {
    return const SimulatorRunState.idle();
  }

  /// Execute a simulation run for [request].
  Future<void> run(SimulatorRunRequest request) async {
    if (state is SimulatorRunLoading) return;
    state = const SimulatorRunState.loading();
    try {
      final result = await ref.read(simulatorServiceProvider).run(request);
      state = SimulatorRunState.success(result);
    } on SimulatorApiException catch (e) {
      state = SimulatorRunState.error(
        e.userMessage,
        details: e.detailMessages,
        statusCode: e.statusCode,
      );
    } catch (e) {
      state = SimulatorRunState.error(e.toString());
    }
  }

  /// Reset to idle (e.g. when the spec changes).
  void reset() => state = const SimulatorRunState.idle();
}

/// Backward-compat alias.
final simulatorRunProvider = simulatorRunControllerProvider;

// ---------------------------------------------------------------------------
// Simulation settings provider
// ---------------------------------------------------------------------------

class SimulatorSettings {
  final int timesteps;
  final int seed;
  final double dtMs;
  final double firingRate;

  const SimulatorSettings({
    this.timesteps = 100,
    this.seed = 1,
    this.dtMs = 1.0,
    this.firingRate = 0.3,
  });

  SimulatorSettings copyWith({
    int? timesteps,
    int? seed,
    double? dtMs,
    double? firingRate,
  }) {
    return SimulatorSettings(
      timesteps: timesteps ?? this.timesteps,
      seed: seed ?? this.seed,
      dtMs: dtMs ?? this.dtMs,
      firingRate: firingRate ?? this.firingRate,
    );
  }

  // Value equality lets the Deploy step's simulator table detect "settings
  // changed since the last run" by comparing against a snapshot (see
  // `simulatorLastRunSettingsProvider` below) instead of tracking a separate
  // dirty flag per field.
  @override
  bool operator ==(Object other) =>
      other is SimulatorSettings &&
      other.timesteps == timesteps &&
      other.seed == seed &&
      other.dtMs == dtMs &&
      other.firingRate == firingRate;

  @override
  int get hashCode => Object.hash(timesteps, seed, dtMs, firingRate);
}

@riverpod
class SimulatorSettingsController extends _$SimulatorSettingsController {
  @override
  SimulatorSettings build(String backendName) {
    return const SimulatorSettings();
  }

  void setTimesteps(int timesteps) =>
      state = state.copyWith(timesteps: timesteps);
  void setSeed(int seed) => state = state.copyWith(seed: seed);
  void setDtMs(double dtMs) => state = state.copyWith(dtMs: dtMs);
  void setFiringRate(double firingRate) =>
      state = state.copyWith(firingRate: firingRate);

  /// Replaces every field at once — used to snap a backend back onto the
  /// shared settings card's current values when its override is cleared.
  void setAll(SimulatorSettings settings) => state = settings;
}

/// Backward-compat alias.
final simulatorSettingsProvider = simulatorSettingsControllerProvider;

// ---------------------------------------------------------------------------
// Shared simulator settings (Deploy step's simulator-family table)
// ---------------------------------------------------------------------------

/// Which simulator backends have their own settings, individually overridden
/// from a target's row in the Deploy step's simulator table. Hand-written
/// rather than `@riverpod`-generated — this is plain, file-local UI state
/// with no async or family dimension, so codegen would add ceremony without
/// benefit.
final simulatorOverriddenBackendsProvider =
    NotifierProvider<SimulatorOverriddenBackendsNotifier, Set<String>>(
      SimulatorOverriddenBackendsNotifier.new,
    );

class SimulatorOverriddenBackendsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void setOverridden(String backend, bool overridden) {
    if (overridden == state.contains(backend)) return;
    state = overridden ? {...state, backend} : ({...state}..remove(backend));
  }
}

/// One shared [SimulatorSettings] value. Editing it is how the Deploy step's
/// simulator table lets Timesteps/Seed/Firing Rate/dt be set once instead of
/// once per target — every backend not in
/// [simulatorOverriddenBackendsProvider] gets pushed this value whenever it
/// changes.
final simulatorSharedSettingsProvider =
    NotifierProvider<SimulatorSharedSettingsNotifier, SimulatorSettings>(
      SimulatorSharedSettingsNotifier.new,
    );

class SimulatorSharedSettingsNotifier extends Notifier<SimulatorSettings> {
  @override
  SimulatorSettings build() => const SimulatorSettings();

  void setTimesteps(int timesteps) =>
      state = state.copyWith(timesteps: timesteps);
  void setSeed(int seed) => state = state.copyWith(seed: seed);
  void setDtMs(double dtMs) => state = state.copyWith(dtMs: dtMs);
  void setFiringRate(double firingRate) =>
      state = state.copyWith(firingRate: firingRate);
}

/// The [SimulatorSettings] each backend was actually launched with on its
/// most recent run, recorded by `runSimulatorBackend` (`simulator_panel.dart`)
/// right before it fires the request. The Deploy step's simulator table
/// compares this snapshot against the backend's *current* live settings
/// (`simulatorSettingsProvider`) to decide whether a completed run is stale —
/// i.e. whether the shared-settings cascade or a per-row override has since
/// changed something, in which case the row's play control should revert
/// from a checkmark back to "needs running" rather than silently keep
/// showing success for parameters that no longer match. Hand-written for the
/// same reason as `simulatorOverriddenBackendsProvider` above: plain,
/// file-local UI state with no async or family dimension.
final simulatorLastRunSettingsProvider =
    NotifierProvider<
      SimulatorLastRunSettingsNotifier,
      Map<String, SimulatorSettings>
    >(SimulatorLastRunSettingsNotifier.new);

class SimulatorLastRunSettingsNotifier
    extends Notifier<Map<String, SimulatorSettings>> {
  @override
  Map<String, SimulatorSettings> build() => const <String, SimulatorSettings>{};

  void record(String backend, SimulatorSettings settings) =>
      state = {...state, backend: settings};
}
