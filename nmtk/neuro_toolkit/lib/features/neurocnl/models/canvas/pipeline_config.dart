import 'package:flutter/foundation.dart';

// Pipeline configuration model.
//
// This model is the authoritative source for the Pipeline tab's state.
// It serialises to JSON and is sent to POST /api/notebook/generate-v2
// as the `pipeline_config` payload — it never touches the CNL spec.
//
// Tab discriminator rule:
//   CanvasState.graph    → Architecture tab → CNL
//   CanvasState.pipeline → Pipeline tab     → training_config.json
//
// NOTE: `dataset` and `framework` are intentionally absent here.
// They are provided by workspaceProvider and injected at the call site
// when the backend payload is assembled.

/// Training strategy for SNN training (how gradients flow back through spikes).
enum TrainingStrategy {
  surrogateGradient('surrogate_gradient', 'Surrogate Gradient'),
  bptt('bptt', 'BPTT (Through Time)'),
  rateCoding('rate_coding', 'Rate Coding');

  const TrainingStrategy(this.backendId, this.displayName);
  final String backendId;
  final String displayName;

  static TrainingStrategy fromBackendId(String id) =>
      TrainingStrategy.values.firstWhere(
        (t) => t.backendId == id,
        orElse: () => TrainingStrategy.surrogateGradient,
      );
}

/// Loss function used during SNN training.
enum LossFunction {
  mseCount('mse_count', 'MSE Count Loss'),
  crossEntropy('cross_entropy', 'Cross-Entropy'),
  membranePotential('membrane_potential', 'Membrane Potential');

  const LossFunction(this.backendId, this.displayName);
  final String backendId;
  final String displayName;

  static LossFunction fromBackendId(String id) =>
      LossFunction.values.firstWhere(
        (l) => l.backendId == id,
        orElse: () => LossFunction.mseCount,
      );
}

/// All configurable parameters for the pipeline tab.
///
/// Defaults are chosen to work out of the box — no manual configuration
/// required for a first run. Dataset and framework selection live in
/// workspaceProvider, not here.
class PipelineConfig {
  const PipelineConfig({
    this.epochs = 50,
    this.seed = 42,
    this.learningRate = 1e-3,
    this.optimizer = PipelineOptimizer.adam,
    this.batchSize = 32,
    this.runEvaluation = true,
    this.trainingStrategy = TrainingStrategy.surrogateGradient,
    this.lossFunction = LossFunction.mseCount,
    this.evalMetrics = const ['accuracy', 'loss'],
    this.exportNir = false,
    this.generatePyDownload = true,
  });

  /// Number of training epochs.
  final int epochs;

  /// Random seed for reproducible weight init / data shuffling.
  final int seed;

  /// Optimizer learning rate.
  final double learningRate;

  /// Optimizer algorithm.
  final PipelineOptimizer optimizer;

  /// Mini-batch size.
  final int batchSize;

  /// Whether to include the Evaluate section in the generated notebook.
  final bool runEvaluation;

  /// Training strategy (how gradients propagate through spikes).
  final TrainingStrategy trainingStrategy;

  /// Loss function used during training.
  final LossFunction lossFunction;

  /// Evaluation metrics to compute when runEvaluation is true.
  final List<String> evalMetrics;

  /// Whether to include NIR export in the Infer/Export section.
  final bool exportNir;

  /// Whether to include a .py script download cell in the notebook.
  final bool generatePyDownload;

  PipelineConfig copyWith({
    int? epochs,
    int? seed,
    double? learningRate,
    PipelineOptimizer? optimizer,
    int? batchSize,
    bool? runEvaluation,
    TrainingStrategy? trainingStrategy,
    LossFunction? lossFunction,
    List<String>? evalMetrics,
    bool? exportNir,
    bool? generatePyDownload,
  }) {
    return PipelineConfig(
      epochs: epochs ?? this.epochs,
      seed: seed ?? this.seed,
      learningRate: learningRate ?? this.learningRate,
      optimizer: optimizer ?? this.optimizer,
      batchSize: batchSize ?? this.batchSize,
      runEvaluation: runEvaluation ?? this.runEvaluation,
      trainingStrategy: trainingStrategy ?? this.trainingStrategy,
      lossFunction: lossFunction ?? this.lossFunction,
      evalMetrics: evalMetrics ?? this.evalMetrics,
      exportNir: exportNir ?? this.exportNir,
      generatePyDownload: generatePyDownload ?? this.generatePyDownload,
    );
  }

  /// Serialises to the JSON shape expected by the backend endpoint.
  ///
  /// NOTE: `dataset` and `framework` keys are injected by the caller from
  /// workspaceProvider — they are not fields of this model.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'epochs': epochs,
    'seed': seed,
    'learning_rate': learningRate,
    'optimizer': optimizer.backendId,
    'batch_size': batchSize,
    'run_evaluation': runEvaluation,
    'training_strategy': trainingStrategy.backendId,
    'loss_function': lossFunction.backendId,
    'eval_metrics': evalMetrics,
    'export_nir': exportNir,
    'generate_py_download': generatePyDownload,
  };

  factory PipelineConfig.fromJson(Map<String, dynamic> json) => PipelineConfig(
    epochs: (json['epochs'] as num?)?.toInt() ?? 50,
    seed: (json['seed'] as num?)?.toInt() ?? 42,
    learningRate: ((json['learning_rate'] as num?) ?? 1e-3).toDouble(),
    optimizer: PipelineOptimizer.fromBackendId(
      (json['optimizer'] as String?) ?? 'Adam',
    ),
    batchSize: (json['batch_size'] as num?)?.toInt() ?? 32,
    runEvaluation: (json['run_evaluation'] as bool?) ?? true,
    trainingStrategy: TrainingStrategy.fromBackendId(
      (json['training_strategy'] as String?) ?? 'surrogate_gradient',
    ),
    lossFunction: LossFunction.fromBackendId(
      (json['loss_function'] as String?) ?? 'mse_count',
    ),
    evalMetrics:
        (json['eval_metrics'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const ['accuracy', 'loss'],
    exportNir: (json['export_nir'] as bool?) ?? false,
    generatePyDownload: (json['generate_py_download'] as bool?) ?? true,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipelineConfig &&
          runtimeType == other.runtimeType &&
          epochs == other.epochs &&
          seed == other.seed &&
          learningRate == other.learningRate &&
          optimizer == other.optimizer &&
          batchSize == other.batchSize &&
          runEvaluation == other.runEvaluation &&
          listEquals(evalMetrics, other.evalMetrics) &&
          exportNir == other.exportNir &&
          generatePyDownload == other.generatePyDownload &&
          trainingStrategy == other.trainingStrategy &&
          lossFunction == other.lossFunction;

  @override
  int get hashCode => Object.hash(
    epochs,
    seed,
    learningRate,
    optimizer,
    batchSize,
    runEvaluation,
    evalMetrics,
    exportNir,
    generatePyDownload,
    trainingStrategy,
    lossFunction,
  );
}

/// Optimizer algorithms.
enum PipelineOptimizer {
  adam('Adam', 'Adam'),
  sgd('SGD', 'SGD'),
  adamw('AdamW', 'AdamW'),
  rmsprop('RMSprop', 'RMSprop');

  const PipelineOptimizer(this.backendId, this.displayName);
  final String backendId;
  final String displayName;

  static PipelineOptimizer fromBackendId(String id) {
    return PipelineOptimizer.values.firstWhere(
      (o) => o.backendId == id,
      orElse: () => PipelineOptimizer.adam,
    );
  }
}
