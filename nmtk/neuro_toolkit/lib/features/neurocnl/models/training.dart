/// Operational class of a training capability — mirrors the backend's
/// [TrainingCategory] enum. We model it as an enum on the Dart side so
/// switch statements in the UI are exhaustive at compile time; unknown
/// values from older backends fall back to [hostTraining] (the safer default
/// — implies no on-device hardware path).
enum TrainingCategoryLabel {
  hostTraining('host_training', 'Train on host', 'Pre-deploy host training'),
  onDeviceLearning(
    'on_device_learning',
    'Sleep-replay on device',
    'Post-deploy on-device learning',
  );

  final String wire;
  final String sectionTitle;
  final String shortLabel;

  const TrainingCategoryLabel(this.wire, this.sectionTitle, this.shortLabel);

  static TrainingCategoryLabel parse(String? wire) {
    return TrainingCategoryLabel.values.firstWhere(
      (c) => c.wire == wire,
      orElse: () => TrainingCategoryLabel.hostTraining,
    );
  }
}

/// Generic training capability descriptor from GET /api/training/capabilities.
class TrainingCapability {
  final String backendName;
  final List<String> supportedTrainingModes;
  final String defaultTrainingMode;
  final String outputFormat;
  final TrainingCategoryLabel category;
  final String description;
  final bool available;
  final String? unavailableReason;

  const TrainingCapability({
    required this.backendName,
    required this.supportedTrainingModes,
    required this.defaultTrainingMode,
    required this.outputFormat,
    required this.category,
    required this.description,
    required this.available,
    this.unavailableReason,
  });

  factory TrainingCapability.fromJson(Map<String, dynamic> json) {
    return TrainingCapability(
      backendName: json['backend_name'] as String,
      supportedTrainingModes: (json['supported_training_modes'] as List)
          .cast<String>(),
      defaultTrainingMode: json['default_training_mode'] as String,
      outputFormat: json['output_format'] as String,
      category: TrainingCategoryLabel.parse(json['category'] as String?),
      description: (json['description'] as String?) ?? '',
      available: json['available'] as bool,
      unavailableReason: json['unavailable_reason'] as String?,
    );
  }
}

/// Response wrapper for capabilities endpoint.
class CapabilitiesResponse {
  final List<TrainingCapability> capabilities;

  const CapabilitiesResponse({required this.capabilities});

  factory CapabilitiesResponse.fromJson(Map<String, dynamic> json) {
    return CapabilitiesResponse(
      capabilities: (json['capabilities'] as List)
          .map((e) => TrainingCapability.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Generic training result from GET /api/training/jobs/{job_id}.
class TrainingResult {
  final String adapterName;
  final String trainingMode;
  final String status;
  final int? nEpochs;
  final double? finalLoss;
  final List<double> lossCurve;
  final List<List<double>> learnedWeights;
  final double? durationSeconds;
  final String? error;
  final Map<String, dynamic>? metadata;

  const TrainingResult({
    required this.adapterName,
    required this.trainingMode,
    required this.status,
    this.nEpochs,
    this.finalLoss,
    required this.lossCurve,
    required this.learnedWeights,
    this.durationSeconds,
    this.error,
    this.metadata,
  });

  factory TrainingResult.fromJson(Map<String, dynamic> json) {
    return TrainingResult(
      adapterName: json['adapter_name'] as String,
      trainingMode: json['training_mode'] as String,
      status: json['status'] as String,
      nEpochs: json['n_epochs'] as int?,
      finalLoss: (json['final_loss'] as num?)?.toDouble(),
      lossCurve: (json['loss_curve'] as List)
          .map((v) => (v as num).toDouble())
          .toList(),
      learnedWeights: (json['learned_weights'] as List)
          .map(
            (row) => (row as List).map((v) => (v as num).toDouble()).toList(),
          )
          .toList(),
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
      error: json['error'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

/// Lightweight response from POST /api/training/run (202 accepted).
class JobResponse {
  final String jobId;
  final String status;

  const JobResponse({required this.jobId, required this.status});

  factory JobResponse.fromJson(Map<String, dynamic> json) => JobResponse(
    jobId: json['job_id'] as String,
    status: json['status'] as String,
  );
}
