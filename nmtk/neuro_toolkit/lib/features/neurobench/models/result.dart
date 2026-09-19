class BenchmarkResult {
  final String id;
  final String benchmarkId;
  final String networkSpecHash;
  final String timestamp;
  final String? targetId;
  final int? quantizationBits;
  final String? encodingMethod;
  final Map<String, dynamic> params;
  final Map<String, double> metrics;
  final Map<String, dynamic>? spikeData;
  final double wallTimeSeconds;
  final int seed;
  final String metricProvenance;

  BenchmarkResult({
    required this.id,
    required this.benchmarkId,
    required this.networkSpecHash,
    required this.timestamp,
    this.targetId,
    this.quantizationBits,
    this.encodingMethod,
    required this.params,
    required this.metrics,
    this.spikeData,
    required this.wallTimeSeconds,
    required this.seed,
    this.metricProvenance = 'cpu_estimated',
  });

  factory BenchmarkResult.fromJson(Map<String, dynamic> json) {
    return BenchmarkResult(
      id: json['id'] as String,
      benchmarkId: json['benchmark_id'] as String,
      networkSpecHash: json['network_spec_hash'] as String,
      timestamp: json['timestamp'] as String,
      targetId: json['target_id'] as String?,
      quantizationBits: json['quantization_bits'] as int?,
      encodingMethod: json['encoding_method'] as String?,
      params: Map<String, dynamic>.from(
        json['params'] as Map<dynamic, dynamic>,
      ),
      metrics: {
        for (final entry in (json['metrics'] as Map<String, dynamic>).entries)
          if (entry.value is num)
            entry.key: (entry.value as num).toDouble(),
      },
      spikeData: json['spike_data'] as Map<String, dynamic>?,
      wallTimeSeconds: (json['wall_time_seconds'] as num).toDouble(),
      seed: json['seed'] as int,
      metricProvenance: json['metric_provenance'] as String? ?? 'cpu_estimated',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'benchmark_id': benchmarkId,
      'network_spec_hash': networkSpecHash,
      'timestamp': timestamp,
      if (targetId != null) 'target_id': targetId,
      if (quantizationBits != null) 'quantization_bits': quantizationBits,
      if (encodingMethod != null) 'encoding_method': encodingMethod,
      'params': params,
      'metrics': metrics,
      if (spikeData != null) 'spike_data': spikeData,
      'wall_time_seconds': wallTimeSeconds,
      'seed': seed,
      'metric_provenance': metricProvenance,
    };
  }
}

enum MetricStatus { improved, regressed, unchanged }

class MetricDiff {
  final String name;
  final double baselineValue;
  final double currentValue;
  final double delta;
  final double deltaPct;
  final MetricStatus status;
  final bool thresholdViolated;

  // Statistical fields
  final double? pValueTtest;
  final double? pValueWilcoxon;
  final bool? isSignificant;
  final double? baselineStd;
  final double? currentStd;
  final List<double>? baselineCi;
  final List<double>? currentCi;

  double? get pValue => pValueTtest ?? pValueWilcoxon;

  MetricDiff({
    required this.name,
    required this.baselineValue,
    required this.currentValue,
    required this.delta,
    required this.deltaPct,
    required this.status,
    required this.thresholdViolated,
    this.pValueTtest,
    this.pValueWilcoxon,
    this.isSignificant,
    this.baselineStd,
    this.currentStd,
    this.baselineCi,
    this.currentCi,
  });

  factory MetricDiff.fromJson(Map<String, dynamic> json) {
    return MetricDiff(
      name: json['name'] as String,
      baselineValue: (json['baseline_value'] as num).toDouble(),
      currentValue: (json['current_value'] as num).toDouble(),
      delta: (json['delta'] as num).toDouble(),
      deltaPct: (json['delta_pct'] as num).toDouble(),
      status: MetricStatus.values.firstWhere(
        (e) => e.name == json['status'] as String,
      ),
      thresholdViolated: json['threshold_violated'] as bool,
      pValueTtest: json['p_value_ttest'] != null
          ? (json['p_value_ttest'] as num).toDouble()
          : null,
      pValueWilcoxon: json['p_value_wilcoxon'] != null
          ? (json['p_value_wilcoxon'] as num).toDouble()
          : null,
      isSignificant: json['is_significant'] as bool?,
      baselineStd: json['baseline_std'] != null
          ? (json['baseline_std'] as num).toDouble()
          : null,
      currentStd: json['current_std'] != null
          ? (json['current_std'] as num).toDouble()
          : null,
      baselineCi: json['baseline_ci'] != null
          ? (json['baseline_ci'] as List)
              .map((e) => (e as num).toDouble())
              .toList()
          : null,
      currentCi: json['current_ci'] != null
          ? (json['current_ci'] as List)
              .map((e) => (e as num).toDouble())
              .toList()
          : null,
    );
  }
}

class DiffResult {
  final dynamic baselineId; // Can be String or List<String>
  final dynamic currentId; // Can be String or List<String>
  final List<MetricDiff> metrics;

  DiffResult({
    required this.baselineId,
    required this.currentId,
    required this.metrics,
  });

  factory DiffResult.fromJson(Map<String, dynamic> json) {
    return DiffResult(
      baselineId: json['baseline_id'],
      currentId: json['current_id'],
      metrics: (json['metrics'] as List<dynamic>)
          .map((m) => MetricDiff.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
}
