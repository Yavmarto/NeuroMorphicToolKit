/// Dart models mirroring the backend simulator contract schemas.
///
/// These types are used by [SimulatorService], [SimulatorProvider], and
/// [SimulatorPanel].  They mirror the Pydantic shapes defined in
/// `backend/app/schemas/simulators.py` exactly so the Studio can decode
/// API responses without shape ambiguity.
library;

import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum SimulatorStatus {
  completed,
  failed,
  unsupported,
  missingDependency,
  preflightFailed;

  static SimulatorStatus fromJson(String value) => switch (value) {
    'completed' => completed,
    'failed' => failed,
    'unsupported' => unsupported,
    'missing_dependency' => missingDependency,
    'preflight_failed' => preflightFailed,
    _ => failed,
  };
}

/// Which of the three outcome buckets a [SimulatorStatus] falls into.
/// `unsupported`/`missingDependency`/`preflightFailed` all read the same way
/// to a user glancing at a status pill — "it ran, but not cleanly" — so they
/// share one bucket rather than three near-identical ones.
enum SimulatorOutcome { success, failure, caveat }

extension SimulatorStatusOutcome on SimulatorStatus {
  SimulatorOutcome get outcome => switch (this) {
    SimulatorStatus.completed => SimulatorOutcome.success,
    SimulatorStatus.failed => SimulatorOutcome.failure,
    SimulatorStatus.unsupported ||
    SimulatorStatus.missingDependency ||
    SimulatorStatus.preflightFailed => SimulatorOutcome.caveat,
  };

  /// Same three labels shown wherever a run's outcome is summarized — the
  /// Deploy step's per-backend status card and its simulator-targets table.
  String get outcomeLabel => switch (outcome) {
    SimulatorOutcome.success => 'Completed',
    SimulatorOutcome.failure => 'Failed',
    SimulatorOutcome.caveat => 'Ran with caveats',
  };

  /// [NmtkTone] for the outcome, for `NmtkStatusBadge`-style pills.
  NmtkTone get outcomeTone => switch (outcome) {
    SimulatorOutcome.success => NmtkTone.success,
    SimulatorOutcome.failure => NmtkTone.danger,
    SimulatorOutcome.caveat => NmtkTone.warning,
  };
}

enum SupportLevel {
  exact,
  approximate,
  unsupported;

  static SupportLevel fromJson(String value) => switch (value) {
    'exact' => exact,
    'approximate' => approximate,
    'unsupported' => unsupported,
    _ => unsupported,
  };

  String toDisplayLabel() => switch (this) {
    exact => 'Exact',
    approximate => 'Approximate',
    unsupported => 'Unsupported',
  };
}

// ---------------------------------------------------------------------------
// SimulatorCapability
// ---------------------------------------------------------------------------

class SimulatorCapability {
  final String backendName;
  final String displayName;
  final bool available;
  final String? unavailableReason;
  final List<String> supportedNirNodes;
  final List<String> unsupportedNirNodes;
  final List<String> approximateSemantics;
  final int maxTimesteps;
  final bool supportsSpikeOutput;
  final bool supportsVoltageTrace;
  final String? requiresOptionalDependency;

  const SimulatorCapability({
    required this.backendName,
    required this.displayName,
    required this.available,
    this.unavailableReason,
    this.supportedNirNodes = const [],
    this.unsupportedNirNodes = const [],
    this.approximateSemantics = const [],
    this.maxTimesteps = 1000,
    this.supportsSpikeOutput = true,
    this.supportsVoltageTrace = false,
    this.requiresOptionalDependency,
  });

  factory SimulatorCapability.fromJson(Map<String, dynamic> json) {
    return SimulatorCapability(
      backendName: json['backend_name'] as String,
      displayName: json['display_name'] as String,
      available: json['available'] as bool,
      unavailableReason: json['unavailable_reason'] as String?,
      supportedNirNodes: List<String>.from(
        json['supported_nir_nodes'] as List? ?? [],
      ),
      unsupportedNirNodes: List<String>.from(
        json['unsupported_nir_nodes'] as List? ?? [],
      ),
      approximateSemantics: List<String>.from(
        json['approximate_semantics'] as List? ?? [],
      ),
      maxTimesteps: (json['max_timesteps'] as int?) ?? 1000,
      supportsSpikeOutput: (json['supports_spike_output'] as bool?) ?? true,
      supportsVoltageTrace: (json['supports_voltage_trace'] as bool?) ?? false,
      requiresOptionalDependency:
          json['requires_optional_dependency'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// StimulusSpec
// ---------------------------------------------------------------------------

class StimulusSpec {
  final String population;
  final Map<String, List<int>> spikes;

  const StimulusSpec({required this.population, required this.spikes});

  Map<String, dynamic> toJson() => {
    'type': 'spike_train',
    'population': population,
    'spikes': spikes.map((k, v) => MapEntry(k, v)),
  };
}

// ---------------------------------------------------------------------------
// SimulatorRunRequest
// ---------------------------------------------------------------------------

class SimulatorRunRequest {
  final String spec;
  final String backendName;
  final int timesteps;
  final int seed;
  final double dtMs;
  final double firingRate;
  final StimulusSpec? stimulus;

  /// Base64 `.nir` graph carrying the learned weights.
  ///
  /// Omitting it is not a neutral default: the backend then compiles the spec,
  /// which stores tensor shape only, so every weight is 0.0, no neuron can reach
  /// threshold, and the run returns an empty raster in milliseconds.
  final String? trainedNirBase64;

  const SimulatorRunRequest({
    required this.spec,
    required this.backendName,
    this.timesteps = 100,
    this.seed = 1,
    this.dtMs = 1.0,
    this.firingRate = 0.3,
    this.stimulus,
    this.trainedNirBase64,
  });

  Map<String, dynamic> toJson() => {
    'spec': spec,
    'backend_name': backendName,
    'timesteps': timesteps,
    'seed': seed,
    'dt_ms': dtMs,
    'firing_rate': firingRate,
    if (stimulus != null) 'stimulus': stimulus!.toJson(),
    if (trainedNirBase64 != null) 'trained_nir_base64': trainedNirBase64,
  };
}

// ---------------------------------------------------------------------------
// SimulatorNIRSummary
// ---------------------------------------------------------------------------

class SimulatorNIRSummary {
  final int nodeCount;
  final int edgeCount;
  final List<String> unsupportedNodes;

  const SimulatorNIRSummary({
    required this.nodeCount,
    required this.edgeCount,
    this.unsupportedNodes = const [],
  });

  factory SimulatorNIRSummary.fromJson(Map<String, dynamic> json) {
    return SimulatorNIRSummary(
      nodeCount: json['node_count'] as int,
      edgeCount: json['edge_count'] as int,
      unsupportedNodes: List<String>.from(
        json['unsupported_nodes'] as List? ?? [],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SimulatorRunResult
// ---------------------------------------------------------------------------

/// One population's spike trains: neuron index (as a string) → firing timesteps.
///
/// The wire shape the backend uses for both a run's output populations and its
/// input stimulus, so the same parser and the same raster painter serve both.
Map<String, List<int>> _parseNeuronSpikes(dynamic raw) {
  if (raw is! Map) return const {};
  return raw.map(
    (index, timesteps) =>
        MapEntry(index as String, List<int>.from(timesteps as List)),
  );
}

/// The spike train that actually drove a run.
///
/// Every simulator run is driven by an input spike train, but until this record
/// existed the frontend only ever saw what came *out* — the raster showed the
/// answer with no way to see the question. When the caller sends no explicit
/// stimulus the backend generates a deterministic Poisson one from the run's
/// seed; [generated] says which happened.
class SimulatorStimulusRecord {
  /// Name of the `nir.Input` node this stimulus drove.
  final String population;
  final int neuronCount;

  /// False when the caller supplied the spike train, true when the backend
  /// generated it from the run's seed.
  final bool generated;

  /// True when the backend capped the payload. Whole neurons are dropped, never
  /// part of one, so every train shown here is complete.
  final bool truncated;

  /// neuron_index_str → [timestep, ...]
  final Map<String, List<int>> spikes;

  const SimulatorStimulusRecord({
    required this.population,
    required this.neuronCount,
    this.generated = true,
    this.truncated = false,
    this.spikes = const {},
  });

  factory SimulatorStimulusRecord.fromJson(Map<String, dynamic> json) {
    return SimulatorStimulusRecord(
      population: json['population'] as String? ?? '',
      neuronCount: (json['neuron_count'] as num?)?.toInt() ?? 0,
      generated: json['generated'] as bool? ?? true,
      truncated: json['truncated'] as bool? ?? false,
      spikes: _parseNeuronSpikes(json['spikes']),
    );
  }
}

class SimulatorRunResult {
  final String backendName;
  final SimulatorStatus status;
  final SupportLevel supportLevel;
  final int timesteps;
  final double durationSeconds;

  /// population → {neuron_index_str → [timestep, ...]}
  final Map<String, Map<String, List<int>>> spikes;

  /// population → {neuron_index_str → [voltage, ...]}
  final Map<String, Map<String, List<double>>> voltages;
  final List<String> warnings;
  final SimulatorNIRSummary nirSummary;

  /// The input spike train this run was driven by. Null on results from a
  /// backend that predates stimulus capture.
  final SimulatorStimulusRecord? stimulus;

  /// Where the simulated network's weights came from, or null when the caller
  /// sent no trained graph. `applied == false` means the run used the spec's
  /// zeros, so an empty raster is the expected outcome rather than a result.
  final TrainedWeightStatus? trainedWeights;
  final Map<String, dynamic> metadata;

  const SimulatorRunResult({
    required this.backendName,
    required this.status,
    required this.supportLevel,
    required this.timesteps,
    required this.durationSeconds,
    this.spikes = const {},
    this.voltages = const {},
    this.warnings = const [],
    required this.nirSummary,
    this.stimulus,
    this.trainedWeights,
    this.metadata = const {},
  });

  factory SimulatorRunResult.fromJson(Map<String, dynamic> json) {
    Map<String, Map<String, List<int>>> parseSpikes(dynamic raw) {
      if (raw is! Map) return {};
      return raw.map(
        (pop, neurons) => MapEntry(pop as String, _parseNeuronSpikes(neurons)),
      );
    }

    Map<String, Map<String, List<double>>> parseVoltages(dynamic raw) {
      if (raw is! Map) return {};
      return raw.map((pop, neurons) {
        final neuronMap = (neurons as Map).map((idx, vs) {
          return MapEntry(
            idx as String,
            (vs as List).map((v) => (v as num).toDouble()).toList(),
          );
        });
        return MapEntry(pop as String, neuronMap);
      });
    }

    return SimulatorRunResult(
      backendName: json['backend_name'] as String,
      status: SimulatorStatus.fromJson(json['status'] as String),
      supportLevel: SupportLevel.fromJson(json['support_level'] as String),
      timesteps: json['timesteps'] as int,
      durationSeconds: (json['duration_seconds'] as num).toDouble(),
      spikes: parseSpikes(json['spikes']),
      voltages: parseVoltages(json['voltages']),
      warnings: List<String>.from(json['warnings'] as List? ?? []),
      nirSummary: SimulatorNIRSummary.fromJson(
        json['nir_summary'] as Map<String, dynamic>,
      ),
      stimulus: json['stimulus'] is Map<String, dynamic>
          ? SimulatorStimulusRecord.fromJson(
              json['stimulus'] as Map<String, dynamic>,
            )
          : null,
      trainedWeights: json['trained_weights'] is Map<String, dynamic>
          ? TrainedWeightStatus.fromJson(
              json['trained_weights'] as Map<String, dynamic>,
            )
          : null,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }
}
