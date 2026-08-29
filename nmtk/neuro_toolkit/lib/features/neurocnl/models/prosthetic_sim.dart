/// Request payload for the prosthetic simulation endpoint.
class ProstheticSimRequest {
  final String spec;
  final String gripperType;
  final double dropHeight;
  final double duration;
  final int nNeurons;
  final bool useSleepWeights;
  final int seed;

  const ProstheticSimRequest({
    required this.spec,
    this.gripperType = 'parallel_jaw',
    this.dropHeight = 0.3,
    this.duration = 2.0,
    this.nNeurons = 50,
    this.useSleepWeights = false,
    this.seed = 42,
  });

  Map<String, dynamic> toJson() => {
    'spec': spec,
    'gripper_type': gripperType,
    'drop_height': dropHeight,
    'duration': duration,
    'n_neurons': nNeurons,
    'use_sleep_weights': useSleepWeights,
    'seed': seed,
  };
}

/// Result returned by the prosthetic simulation endpoint.
class ProstheticSimResult {
  final bool success;
  final List<double> gripHistory;
  final List<double> slipVzHistory;
  final List<double> objectZHistory;
  final double stoppingDistanceM;
  final List<String>? frames;
  final double wallTimeSeconds;

  const ProstheticSimResult({
    required this.success,
    required this.gripHistory,
    required this.slipVzHistory,
    required this.objectZHistory,
    required this.stoppingDistanceM,
    this.frames,
    required this.wallTimeSeconds,
  });

  factory ProstheticSimResult.fromJson(Map<String, dynamic> json) {
    return ProstheticSimResult(
      success: json['success'] as bool,
      gripHistory: (json['grip_history'] as List)
          .map((v) => (v as num).toDouble())
          .toList(),
      slipVzHistory: (json['slip_vz_history'] as List)
          .map((v) => (v as num).toDouble())
          .toList(),
      objectZHistory: (json['object_z_history'] as List)
          .map((v) => (v as num).toDouble())
          .toList(),
      stoppingDistanceM: (json['stopping_distance_m'] as num).toDouble(),
      frames: json['frames'] != null
          ? (json['frames'] as List).cast<String>()
          : null,
      wallTimeSeconds: (json['wall_time_seconds'] as num).toDouble(),
    );
  }
}
