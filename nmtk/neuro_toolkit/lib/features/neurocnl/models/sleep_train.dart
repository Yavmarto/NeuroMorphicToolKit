/// Request payload for the sleep-training endpoint.
class SleepTrainRequest {
  final String spec;
  final List<Map<String, double>> memoryBuffer;
  final int nEpochs;
  final double homeostasisFactor;

  const SleepTrainRequest({
    required this.spec,
    required this.memoryBuffer,
    this.nEpochs = 10,
    this.homeostasisFactor = 0.1,
  });

  Map<String, dynamic> toJson() => {
    'spec': spec,
    'memory_buffer': memoryBuffer,
    'n_epochs': nEpochs,
    'homeostasis_factor': homeostasisFactor,
  };
}

/// Result returned by the sleep-training endpoint.
class SleepTrainResult {
  final List<double> lossCurve;
  final int nEpochs;
  final double finalLoss;
  final List<List<double>> learnedWeights;

  const SleepTrainResult({
    required this.lossCurve,
    required this.nEpochs,
    required this.finalLoss,
    required this.learnedWeights,
  });

  factory SleepTrainResult.fromJson(Map<String, dynamic> json) {
    return SleepTrainResult(
      lossCurve: (json['loss_curve'] as List)
          .map((v) => (v as num).toDouble())
          .toList(),
      nEpochs: json['n_epochs'] as int,
      finalLoss: (json['final_loss'] as num).toDouble(),
      learnedWeights: (json['learned_weights'] as List)
          .map(
            (row) => (row as List).map((v) => (v as num).toDouble()).toList(),
          )
          .toList(),
    );
  }
}
