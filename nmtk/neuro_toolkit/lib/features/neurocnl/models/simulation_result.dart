/// Probe data from a simulation run.
class ProbeData {
  final String type; // "spike_raster" or "continuous"
  final List<double> times;
  final List<int>? neuronIndices;
  final List<double>? values;

  const ProbeData({
    required this.type,
    required this.times,
    this.neuronIndices,
    this.values,
  });

  factory ProbeData.fromJson(Map<String, dynamic> json) {
    return ProbeData(
      type: json['type'] as String,
      times: (json['times'] as List).map((t) => (t as num).toDouble()).toList(),
      neuronIndices: json['neuron_indices'] != null
          ? (json['neuron_indices'] as List)
                .map((i) => (i as num).toInt())
                .toList()
          : null,
      values: json['values'] != null
          ? (json['values'] as List).map((v) => (v as num).toDouble()).toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type,
    'times': times,
    if (neuronIndices != null) 'neuron_indices': neuronIndices,
    if (values != null) 'values': values,
  };
}

/// Summary statistics from a simulation run.
class SimulationSummary {
  final int sensorySpikeCount;
  final int motorSpikeCount;
  final double sensoryMeanRate;
  final double motorMeanRate;
  final double? firstOutputSpike;
  final double? inputToOutputLatency;

  const SimulationSummary({
    required this.sensorySpikeCount,
    required this.motorSpikeCount,
    required this.sensoryMeanRate,
    required this.motorMeanRate,
    this.firstOutputSpike,
    this.inputToOutputLatency,
  });

  factory SimulationSummary.fromJson(Map<String, dynamic> json) {
    return SimulationSummary(
      sensorySpikeCount: json['sensory_spike_count'] as int? ?? 0,
      motorSpikeCount: json['motor_spike_count'] as int? ?? 0,
      sensoryMeanRate: (json['sensory_mean_rate'] as num?)?.toDouble() ?? 0.0,
      motorMeanRate: (json['motor_mean_rate'] as num?)?.toDouble() ?? 0.0,
      firstOutputSpike: (json['first_output_spike'] as num?)?.toDouble(),
      inputToOutputLatency: (json['input_to_output_latency'] as num?)
          ?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'sensory_spike_count': sensorySpikeCount,
    'motor_spike_count': motorSpikeCount,
    'sensory_mean_rate': sensoryMeanRate,
    'motor_mean_rate': motorMeanRate,
    'first_output_spike': firstOutputSpike,
    'input_to_output_latency': inputToOutputLatency,
  };
}

/// Full simulation response from /api/simulate.
class SimulationResult {
  final double duration;
  final double dt;
  final int timesteps;
  final Map<String, ProbeData> probes;
  final SimulationSummary summary;
  final double wallTimeSeconds;

  const SimulationResult({
    required this.duration,
    required this.dt,
    required this.timesteps,
    required this.probes,
    required this.summary,
    required this.wallTimeSeconds,
  });

  factory SimulationResult.fromJson(Map<String, dynamic> json) {
    final probesMap = <String, ProbeData>{};
    final rawProbes = json['probes'] as Map<String, dynamic>;
    for (final entry in rawProbes.entries) {
      probesMap[entry.key] = ProbeData.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    return SimulationResult(
      duration: (json['duration'] as num).toDouble(),
      dt: (json['dt'] as num).toDouble(),
      timesteps: json['timesteps'] as int,
      probes: probesMap,
      summary: SimulationSummary.fromJson(
        json['summary'] as Map<String, dynamic>,
      ),
      wallTimeSeconds: (json['wall_time_seconds'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'duration': duration,
    'dt': dt,
    'timesteps': timesteps,
    'probes': probes.map(
      (key, value) => MapEntry<String, dynamic>(key, value.toJson()),
    ),
    'summary': summary.toJson(),
    'wall_time_seconds': wallTimeSeconds,
  };
}
