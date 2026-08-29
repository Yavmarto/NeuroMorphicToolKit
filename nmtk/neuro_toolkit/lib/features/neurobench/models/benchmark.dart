class InputSpec {
  final String type;
  final Map<String, dynamic>? syntheticConfig;
  final String? recordingSessionId;
  final String? dataPath;

  InputSpec({
    required this.type,
    this.syntheticConfig,
    this.recordingSessionId,
    this.dataPath,
  });

  factory InputSpec.fromJson(Map<String, dynamic> json) {
    return InputSpec(
      type: json['type'] as String,
      syntheticConfig: json['synthetic_config'] as Map<String, dynamic>?,
      recordingSessionId: json['recording_session_id'] as String?,
      dataPath: json['data_path'] as String?,
    );
  }
}

class ScoringConfig {
  final String primaryMetric;
  final List<String> secondaryMetrics;
  final bool higherIsBetter;
  final double passThreshold;

  ScoringConfig({
    required this.primaryMetric,
    required this.secondaryMetrics,
    required this.higherIsBetter,
    required this.passThreshold,
  });

  factory ScoringConfig.fromJson(Map<String, dynamic> json) {
    return ScoringConfig(
      primaryMetric: json['primary_metric'] as String,
      secondaryMetrics: List<String>.from(
        json['secondary_metrics'] as Iterable<dynamic>,
      ),
      higherIsBetter: json['higher_is_better'] as bool,
      passThreshold: (json['pass_threshold'] as num).toDouble(),
    );
  }
}

class BenchmarkDefinition {
  final String id;
  final String name;
  final String description;
  final String taskType;
  final InputSpec inputSpec;
  final List<String> assertions;
  final ScoringConfig scoring;
  final Map<String, dynamic> defaultParams;
  final bool builtin;

  BenchmarkDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.taskType,
    required this.inputSpec,
    required this.assertions,
    required this.scoring,
    required this.defaultParams,
    required this.builtin,
  });

  factory BenchmarkDefinition.fromJson(Map<String, dynamic> json) {
    return BenchmarkDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      taskType: json['task_type'] as String,
      inputSpec: InputSpec.fromJson(json['input_spec'] as Map<String, dynamic>),
      assertions: List<String>.from(json['assertions'] as Iterable<dynamic>),
      scoring: ScoringConfig.fromJson(json['scoring'] as Map<String, dynamic>),
      defaultParams: Map<String, dynamic>.from(
        json['default_params'] as Map<dynamic, dynamic>,
      ),
      builtin: json['builtin'] as bool,
    );
  }
}
