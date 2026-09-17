import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/node_geometry.dart';

// ── Port types ─────────────────────────────────────────────────────────────

enum PortType { data, spikes, membrane, loss, gradients, model, metrics, any }

class PortSpec {
  const PortSpec(this.id, this.type, {this.optional = false, this.hint});
  final String id;
  final PortType type;
  final bool optional;
  final String? hint;
}

// ── Pipeline phase identifier ──────────────────────────────────────────────

enum PipelinePhaseId { train, eval, infer }

/// Client-only metadata used to defer local .pt/.npy uploads until notebook
/// generation. Generation strips these keys before sending pipeline JSON.
const String kDatasetPathScopeKey = 'dataset_path_scope';
const String kDatasetFileNameKey = 'dataset_file_name';
const String kClientDatasetPathScope = 'client';
const String kServerDatasetPathScope = 'server';

// ── Node categories ────────────────────────────────────────────────────────

enum PipelineDagCategory {
  data,
  timeControl,
  network,
  loss,
  backward,
  optimiser,
  scheduler,
  metrics,
  export,
  lava,
}

// ── Node types ─────────────────────────────────────────────────────────────

enum PipelineDagNodeType {
  // Data
  dataLoader,
  testLoader,
  spikeEncoder,
  spikeGenerator,
  // Time control
  timeLoop,
  validationLoop,
  // Network
  forwardPass,
  spikeRecorder,
  membraneRecorder,
  stateReset,
  spikeDomainFilter,
  // Loss
  mseCountLoss,
  ceCountLoss,
  crossEntropyLoss,
  membraneLoss,
  l1SpikeReg,
  l2SpikeReg,
  // Backward
  surrogateBackward,
  bpttBackward,
  customGradientStep,
  // Optimiser
  adamOptimiser,
  sgdOptimiser,
  adamwOptimiser,
  rmspropOptimiser,
  lbiOptimizer,
  // Scheduler
  stepLR,
  cosineAnnealingLR,
  exponentialLR,
  reduceLROnPlateau,
  // Training utilities
  gradientClip,
  weightClip,
  earlyStopping,
  // Metrics
  accuracyMetric,
  f1Score,
  confusionMatrix,
  lossLogger,
  spikeRateLogger,
  spikeCountMetric,
  latencyMetric,
  // Export
  nirExporter,
  akidaExporter,
  pyExporter,
  torchScriptExporter,
  // Lava-specific
  lavaProcessGraph,
  lavaSim,
  lavaHwConfig,
  loihiExporter,
}

extension PipelineDagNodeTypeX on PipelineDagNodeType {
  String get label => switch (this) {
    PipelineDagNodeType.dataLoader => 'Data Loader',
    PipelineDagNodeType.testLoader => 'Test Loader',
    PipelineDagNodeType.spikeEncoder => 'Spike Encoder',
    PipelineDagNodeType.spikeGenerator => 'Spike Generator',
    PipelineDagNodeType.timeLoop => 'Time Loop',
    PipelineDagNodeType.validationLoop => 'Validation Loop',
    PipelineDagNodeType.forwardPass => 'Forward Pass',
    PipelineDagNodeType.spikeRecorder => 'Spike Recorder',
    PipelineDagNodeType.membraneRecorder => 'Membrane Recorder',
    PipelineDagNodeType.stateReset => 'State Reset',
    PipelineDagNodeType.spikeDomainFilter => 'Spike-Domain Filter',
    PipelineDagNodeType.mseCountLoss => 'MSE Count Loss',
    PipelineDagNodeType.ceCountLoss => 'CE Count Loss',
    PipelineDagNodeType.crossEntropyLoss => 'Cross-Entropy Loss',
    PipelineDagNodeType.membraneLoss => 'Membrane Loss',
    PipelineDagNodeType.l1SpikeReg => 'L1 Spike Regularization',
    PipelineDagNodeType.l2SpikeReg => 'L2 Spike Regularization',
    PipelineDagNodeType.surrogateBackward => 'Surrogate Backward',
    PipelineDagNodeType.bpttBackward => 'BPTT Backward',
    PipelineDagNodeType.customGradientStep => 'Custom Gradient Step',
    PipelineDagNodeType.adamOptimiser => 'Adam Optimiser',
    PipelineDagNodeType.sgdOptimiser => 'SGD Optimiser',
    PipelineDagNodeType.adamwOptimiser => 'AdamW Optimiser',
    PipelineDagNodeType.rmspropOptimiser => 'RMSprop Optimiser',
    PipelineDagNodeType.lbiOptimizer => 'Linearized Bregman Iteration',
    PipelineDagNodeType.stepLR => 'Step LR',
    PipelineDagNodeType.cosineAnnealingLR => 'Cosine Annealing LR',
    PipelineDagNodeType.exponentialLR => 'Exponential LR',
    PipelineDagNodeType.reduceLROnPlateau => 'Reduce LR on Plateau',
    PipelineDagNodeType.gradientClip => 'Gradient Clip',
    PipelineDagNodeType.weightClip => 'Weight Clip',
    PipelineDagNodeType.earlyStopping => 'Early Stopping',
    PipelineDagNodeType.accuracyMetric => 'Accuracy',
    PipelineDagNodeType.f1Score => 'F1 Score',
    PipelineDagNodeType.confusionMatrix => 'Confusion Matrix',
    PipelineDagNodeType.lossLogger => 'Loss Logger',
    PipelineDagNodeType.spikeRateLogger => 'Spike Rate Logger',
    PipelineDagNodeType.spikeCountMetric => 'Spike Count Metric',
    PipelineDagNodeType.latencyMetric => 'Latency (TTFS) Metric',
    PipelineDagNodeType.nirExporter => 'NIR Exporter',
    PipelineDagNodeType.akidaExporter => 'Akida Exporter',
    PipelineDagNodeType.pyExporter => 'Python Exporter',
    PipelineDagNodeType.torchScriptExporter => 'TorchScript Exporter',
    PipelineDagNodeType.lavaProcessGraph => 'Lava Process Graph',
    PipelineDagNodeType.lavaSim => 'Lava Simulator',
    PipelineDagNodeType.lavaHwConfig => 'Lava HW Config',
    PipelineDagNodeType.loihiExporter => 'Loihi Exporter',
  };

  PipelineDagCategory get category => switch (this) {
    PipelineDagNodeType.dataLoader => PipelineDagCategory.data,
    PipelineDagNodeType.testLoader => PipelineDagCategory.data,
    PipelineDagNodeType.spikeEncoder => PipelineDagCategory.data,
    PipelineDagNodeType.spikeGenerator => PipelineDagCategory.data,
    PipelineDagNodeType.timeLoop => PipelineDagCategory.timeControl,
    PipelineDagNodeType.validationLoop => PipelineDagCategory.timeControl,
    PipelineDagNodeType.forwardPass => PipelineDagCategory.network,
    PipelineDagNodeType.spikeRecorder => PipelineDagCategory.network,
    PipelineDagNodeType.membraneRecorder => PipelineDagCategory.network,
    PipelineDagNodeType.stateReset => PipelineDagCategory.network,
    PipelineDagNodeType.spikeDomainFilter => PipelineDagCategory.network,
    PipelineDagNodeType.mseCountLoss => PipelineDagCategory.loss,
    PipelineDagNodeType.ceCountLoss => PipelineDagCategory.loss,
    PipelineDagNodeType.crossEntropyLoss => PipelineDagCategory.loss,
    PipelineDagNodeType.membraneLoss => PipelineDagCategory.loss,
    PipelineDagNodeType.l1SpikeReg => PipelineDagCategory.loss,
    PipelineDagNodeType.l2SpikeReg => PipelineDagCategory.loss,
    PipelineDagNodeType.surrogateBackward => PipelineDagCategory.backward,
    PipelineDagNodeType.bpttBackward => PipelineDagCategory.backward,
    PipelineDagNodeType.customGradientStep => PipelineDagCategory.backward,
    PipelineDagNodeType.adamOptimiser => PipelineDagCategory.optimiser,
    PipelineDagNodeType.sgdOptimiser => PipelineDagCategory.optimiser,
    PipelineDagNodeType.adamwOptimiser => PipelineDagCategory.optimiser,
    PipelineDagNodeType.rmspropOptimiser => PipelineDagCategory.optimiser,
    PipelineDagNodeType.lbiOptimizer => PipelineDagCategory.optimiser,
    PipelineDagNodeType.stepLR => PipelineDagCategory.scheduler,
    PipelineDagNodeType.cosineAnnealingLR => PipelineDagCategory.scheduler,
    PipelineDagNodeType.exponentialLR => PipelineDagCategory.scheduler,
    PipelineDagNodeType.reduceLROnPlateau => PipelineDagCategory.scheduler,
    PipelineDagNodeType.earlyStopping => PipelineDagCategory.scheduler,
    PipelineDagNodeType.gradientClip => PipelineDagCategory.backward,
    PipelineDagNodeType.weightClip => PipelineDagCategory.optimiser,
    PipelineDagNodeType.accuracyMetric => PipelineDagCategory.metrics,
    PipelineDagNodeType.f1Score => PipelineDagCategory.metrics,
    PipelineDagNodeType.confusionMatrix => PipelineDagCategory.metrics,
    PipelineDagNodeType.lossLogger => PipelineDagCategory.metrics,
    PipelineDagNodeType.spikeRateLogger => PipelineDagCategory.metrics,
    PipelineDagNodeType.spikeCountMetric => PipelineDagCategory.metrics,
    PipelineDagNodeType.latencyMetric => PipelineDagCategory.metrics,
    PipelineDagNodeType.nirExporter => PipelineDagCategory.export,
    PipelineDagNodeType.akidaExporter => PipelineDagCategory.export,
    PipelineDagNodeType.pyExporter => PipelineDagCategory.export,
    PipelineDagNodeType.torchScriptExporter => PipelineDagCategory.export,
    PipelineDagNodeType.lavaProcessGraph => PipelineDagCategory.lava,
    PipelineDagNodeType.lavaSim => PipelineDagCategory.lava,
    PipelineDagNodeType.lavaHwConfig => PipelineDagCategory.lava,
    PipelineDagNodeType.loihiExporter => PipelineDagCategory.lava,
  };

  /// Backend framework IDs this node applies to. Empty = all frameworks.
  Set<String> get frameworks => switch (this) {
    // Lava-specific
    PipelineDagNodeType.lavaProcessGraph ||
    PipelineDagNodeType.lavaSim ||
    PipelineDagNodeType.lavaHwConfig ||
    PipelineDagNodeType.loihiExporter => const {'lava', 'lava_sim'},
    // snnTorch-specific
    PipelineDagNodeType.mseCountLoss ||
    PipelineDagNodeType.ceCountLoss ||
    PipelineDagNodeType.membraneLoss ||
    PipelineDagNodeType.l1SpikeReg ||
    PipelineDagNodeType.l2SpikeReg ||
    PipelineDagNodeType.surrogateBackward ||
    PipelineDagNodeType.bpttBackward ||
    PipelineDagNodeType.spikeEncoder ||
    PipelineDagNodeType.spikeGenerator ||
    PipelineDagNodeType.spikeRecorder ||
    PipelineDagNodeType.membraneRecorder ||
    PipelineDagNodeType.timeLoop ||
    PipelineDagNodeType.gradientClip ||
    PipelineDagNodeType.weightClip ||
    PipelineDagNodeType.spikeCountMetric ||
    PipelineDagNodeType.latencyMetric => const {'snntorch_sim'},
    // Generic (all frameworks)
    _ => const {},
  };

  Map<String, dynamic> get defaultParameters => switch (this) {
    PipelineDagNodeType.dataLoader => {
      'batch_size': 32,
      'shuffle': true,
      'format': 'auto',
      'time_window_ms': 1,
      'dataset_path': '',
    },
    PipelineDagNodeType.testLoader => {
      'batch_size': 32,
      'shuffle': false,
      'format': 'auto',
      'time_window_ms': 1,
      'dataset_path': '',
      'load_best_checkpoint': true,
    },
    PipelineDagNodeType.timeLoop => {'num_steps': 25},
    PipelineDagNodeType.validationLoop => {
      'every_n_epochs': 1,
      'save_best_checkpoint': true,
      'checkpoint_metric': 'val_accuracy',
      'checkpoint_mode': 'max',
    },
    PipelineDagNodeType.mseCountLoss => {
      'correct_rate': 0.8,
      'incorrect_rate': 0.2,
    },
    PipelineDagNodeType.adamOptimiser => {
      'lr': 0.001,
      'weight_decay': 0.0,
      'beta1': 0.9,
      'beta2': 0.999,
    },
    PipelineDagNodeType.sgdOptimiser => {
      'lr': 0.01,
      'momentum': 0.9,
      'nesterov': false,
    },
    PipelineDagNodeType.adamwOptimiser => {'lr': 0.001, 'weight_decay': 0.01},
    PipelineDagNodeType.rmspropOptimiser => {'lr': 0.01, 'alpha': 0.99},
    PipelineDagNodeType.stepLR => {'step_size': 10, 'gamma': 0.1},
    PipelineDagNodeType.cosineAnnealingLR => {'T_max': 50, 'eta_min': 0.0},
    PipelineDagNodeType.exponentialLR => {'gamma': 0.95},
    PipelineDagNodeType.reduceLROnPlateau => {
      'mode': 'min',
      'factor': 0.1,
      'patience': 10,
      'min_lr': 0.0,
    },
    PipelineDagNodeType.gradientClip => {'max_norm': 1.0},
    PipelineDagNodeType.weightClip => {'min_weight': -1.0, 'max_weight': 1.0},
    PipelineDagNodeType.earlyStopping => {'patience': 10, 'min_delta': 0.0},
    PipelineDagNodeType.latencyMetric => {'default_latency': -1},
    PipelineDagNodeType.accuracyMetric => {'top_k': 1},
    PipelineDagNodeType.f1Score => {'average': 'macro'},
    PipelineDagNodeType.spikeEncoder => {'encoding': 'rate', 'time_window': 25},
    PipelineDagNodeType.spikeGenerator => {
      'n_neurons': 1,
      'n_timesteps': 100,
      'pattern': 'isi_regular',
      'isi_period': 10,
      'rate_hz': 10.0,
      'seed': 42,
    },
    PipelineDagNodeType.nirExporter => {'filename': 'model.nir'},
    // Deliberately not framework-gated: snntorch_sim is the only target with a
    // training adapter, so the node has to be available on the run that
    // actually trains. weight_bits is what Akida accepts (1, 2, 4 or 8).
    // deploy_bundle defaults on: the bundle is the only artifact any deploy
    // control looks for, so converting without one leaves the model stranded in
    // the workspace. eval_samples caps what travels with it — the host limits a
    // bundle to 32 MB and the launcher its base64 to 45 MB.
    PipelineDagNodeType.akidaExporter => {
      'filename': 'model.fbz',
      'weight_bits': 4,
      'deploy_bundle': true,
      'eval_samples': 2000,
    },
    PipelineDagNodeType.pyExporter => {'filename': 'model.py'},
    PipelineDagNodeType.lavaSim => {'num_steps': 25, 'backend': 'loihi2sim'},
    PipelineDagNodeType.lavaProcessGraph => {'num_steps': 25},
    PipelineDagNodeType.forwardPass => {},
    PipelineDagNodeType.surrogateBackward => {
      'function': 'fast_sigmoid',
      'slope': 25.0,
    },
    PipelineDagNodeType.l1SpikeReg => {'weight': 1e-5, 'target_layer': ''},
    PipelineDagNodeType.l2SpikeReg => {'weight': 1e-5, 'target_layer': ''},
    PipelineDagNodeType.lbiOptimizer => {
      'lr': 0.001,
      'lambda_reg': 0.01,
      'kappa': 10.0,
    },
    PipelineDagNodeType.customGradientStep => {
      'expression': '',
      'clip_value': 0.0,
    },
    PipelineDagNodeType.spikeDomainFilter => {
      'filter_type': 'threshold',
      'window': 5,
      'threshold': 0.5,
    },
    _ => const {},
  };

  List<PortSpec> get inputPorts => switch (this) {
    PipelineDagNodeType.spikeEncoder => const [PortSpec('data', PortType.data)],
    PipelineDagNodeType.timeLoop => const [PortSpec('spikes', PortType.spikes)],
    PipelineDagNodeType.validationLoop => const [
      PortSpec('model', PortType.model),
      PortSpec('val_data', PortType.data, optional: true),
    ],
    PipelineDagNodeType.forwardPass => const [
      PortSpec('input', PortType.any),
      PortSpec('model', PortType.model, optional: true),
    ],
    PipelineDagNodeType.spikeRecorder || PipelineDagNodeType.membraneRecorder =>
      const [PortSpec('input', PortType.any)],
    PipelineDagNodeType.stateReset => const [PortSpec('model', PortType.model)],
    PipelineDagNodeType.spikeDomainFilter => const [
      PortSpec('spikes', PortType.spikes),
    ],
    PipelineDagNodeType.mseCountLoss ||
    PipelineDagNodeType.ceCountLoss ||
    PipelineDagNodeType.crossEntropyLoss ||
    PipelineDagNodeType.membraneLoss => const [
      PortSpec('spikes', PortType.spikes),
      PortSpec('labels', PortType.any),
    ],
    PipelineDagNodeType.l1SpikeReg || PipelineDagNodeType.l2SpikeReg => const [
      PortSpec('spikes', PortType.spikes),
      PortSpec('loss_in', PortType.loss, optional: true),
    ],
    PipelineDagNodeType.surrogateBackward ||
    PipelineDagNodeType.bpttBackward ||
    PipelineDagNodeType.customGradientStep => const [
      PortSpec('loss', PortType.loss),
    ],
    PipelineDagNodeType.adamOptimiser ||
    PipelineDagNodeType.sgdOptimiser ||
    PipelineDagNodeType.adamwOptimiser ||
    PipelineDagNodeType.rmspropOptimiser ||
    PipelineDagNodeType.lbiOptimizer => const [
      PortSpec('gradients', PortType.gradients),
    ],
    PipelineDagNodeType.stepLR ||
    PipelineDagNodeType.cosineAnnealingLR ||
    PipelineDagNodeType.exponentialLR ||
    PipelineDagNodeType.weightClip => const [PortSpec('model', PortType.model)],
    PipelineDagNodeType.reduceLROnPlateau ||
    PipelineDagNodeType.earlyStopping => const [
      PortSpec('model', PortType.model),
      PortSpec('metric', PortType.metrics, optional: true),
    ],
    PipelineDagNodeType.gradientClip => const [
      PortSpec('gradients', PortType.gradients),
    ],
    PipelineDagNodeType.accuracyMetric ||
    PipelineDagNodeType.f1Score ||
    PipelineDagNodeType.confusionMatrix ||
    PipelineDagNodeType.spikeCountMetric ||
    PipelineDagNodeType.latencyMetric => const [
      PortSpec('spikes', PortType.spikes),
      PortSpec('labels', PortType.any),
    ],
    PipelineDagNodeType.lossLogger => const [PortSpec('loss', PortType.loss)],
    PipelineDagNodeType.spikeRateLogger => const [
      PortSpec('spikes', PortType.spikes),
    ],
    PipelineDagNodeType.nirExporter ||
    PipelineDagNodeType.akidaExporter ||
    PipelineDagNodeType.torchScriptExporter => const [
      PortSpec('model', PortType.model),
    ],
    PipelineDagNodeType.pyExporter => const [
      PortSpec('model', PortType.model, optional: true),
    ],
    _ => const [],
  };

  List<PortSpec> get outputPorts => switch (this) {
    PipelineDagNodeType.dataLoader ||
    PipelineDagNodeType.testLoader ||
    PipelineDagNodeType.spikeGenerator => const [
      PortSpec('data', PortType.data),
      PortSpec('labels', PortType.any),
    ],
    PipelineDagNodeType.spikeEncoder => const [
      PortSpec('spikes', PortType.spikes),
    ],
    PipelineDagNodeType.timeLoop => const [PortSpec('spikes', PortType.spikes)],
    PipelineDagNodeType.validationLoop => const [
      PortSpec('metrics', PortType.metrics),
    ],
    PipelineDagNodeType.forwardPass => const [
      PortSpec(
        'spikes',
        PortType.spikes,
        hint: 'Connect to loss / metric / logger nodes',
      ),
      PortSpec('membrane', PortType.membrane),
      PortSpec(
        'model',
        PortType.model,
        optional: true,
        hint: 'Connect to State Reset or scheduler',
      ),
    ],
    PipelineDagNodeType.spikeRecorder => const [
      PortSpec('spikes', PortType.spikes),
    ],
    PipelineDagNodeType.membraneRecorder => const [
      PortSpec('membrane', PortType.membrane),
    ],
    PipelineDagNodeType.stateReset => const [PortSpec('model', PortType.model)],
    PipelineDagNodeType.spikeDomainFilter => const [
      PortSpec('spikes', PortType.spikes),
    ],
    PipelineDagNodeType.mseCountLoss ||
    PipelineDagNodeType.ceCountLoss ||
    PipelineDagNodeType.crossEntropyLoss ||
    PipelineDagNodeType.membraneLoss ||
    PipelineDagNodeType.l1SpikeReg ||
    PipelineDagNodeType.l2SpikeReg => const [PortSpec('loss', PortType.loss)],
    PipelineDagNodeType.surrogateBackward ||
    PipelineDagNodeType.bpttBackward ||
    PipelineDagNodeType.customGradientStep => const [
      PortSpec('gradients', PortType.gradients),
    ],
    PipelineDagNodeType.adamOptimiser ||
    PipelineDagNodeType.sgdOptimiser ||
    PipelineDagNodeType.adamwOptimiser ||
    PipelineDagNodeType.rmspropOptimiser ||
    PipelineDagNodeType.lbiOptimizer => const [
      PortSpec('model', PortType.model),
    ],
    PipelineDagNodeType.stepLR ||
    PipelineDagNodeType.cosineAnnealingLR ||
    PipelineDagNodeType.exponentialLR => const [
      PortSpec('model', PortType.model),
    ],
    PipelineDagNodeType.accuracyMetric ||
    PipelineDagNodeType.f1Score ||
    PipelineDagNodeType.confusionMatrix => const [
      PortSpec('metrics', PortType.metrics),
    ],
    _ => const [],
  };
}

// ── Palette candidate set ──────────────────────────────────────────────────

/// The node types a user may add to [phase], given the platforms selected for
/// the workspace.
///
/// Single source of truth for every "add a node" surface — the bottom-bar
/// palette and the port-anchored connect palette both call this. Keeping the
/// phase→category table here rather than inlined in a screen is what stops the
/// two palettes from offering different node sets.
List<PipelineDagNodeType> pipelineNodeTypesFor(
  PipelinePhaseId phase,
  Set<String> selectedPlatforms,
) {
  final Set<PipelineDagCategory> phaseCategories = switch (phase) {
    PipelinePhaseId.train => const {
      PipelineDagCategory.data,
      PipelineDagCategory.timeControl,
      PipelineDagCategory.network,
      PipelineDagCategory.loss,
      PipelineDagCategory.backward,
      PipelineDagCategory.optimiser,
      PipelineDagCategory.scheduler,
      PipelineDagCategory.lava,
      PipelineDagCategory.export,
    },
    PipelinePhaseId.eval => const {
      PipelineDagCategory.data,
      PipelineDagCategory.network,
      PipelineDagCategory.metrics,
      PipelineDagCategory.lava,
    },
    PipelinePhaseId.infer => const {
      PipelineDagCategory.data,
      PipelineDagCategory.network,
      PipelineDagCategory.export,
      PipelineDagCategory.lava,
    },
  };

  return PipelineDagNodeType.values.where((PipelineDagNodeType t) {
    final bool frameworkOk =
        t.frameworks.isEmpty || t.frameworks.any(selectedPlatforms.contains);
    return frameworkOk && phaseCategories.contains(t.category);
  }).toList();
}

// ── Node ───────────────────────────────────────────────────────────────────

class PipelineDagNode {
  const PipelineDagNode({
    required this.id,
    required this.type,
    this.customComponentId,
    this.x = 0,
    this.y = 0,
    this.parameters = const {},
  });

  final String id;
  final PipelineDagNodeType type;

  /// Stable custom-node identity. [type] remains the built-in pipeline role
  /// used for topology, ports, and backwards-compatible notebook generation.
  final String? customComponentId;
  final double x;
  final double y;
  final Map<String, dynamic> parameters;

  PipelineDagNode copyWith({
    String? id,
    PipelineDagNodeType? type,
    String? customComponentId,
    bool clearCustomComponentId = false,
    double? x,
    double? y,
    Map<String, dynamic>? parameters,
  }) => PipelineDagNode(
    id: id ?? this.id,
    type: type ?? this.type,
    customComponentId: clearCustomComponentId
        ? null
        : customComponentId ?? this.customComponentId,
    x: x ?? this.x,
    y: y ?? this.y,
    parameters: parameters ?? this.parameters,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    if (customComponentId != null) 'custom_component_id': customComponentId,
    'x': x,
    'y': y,
    'parameters': parameters,
  };

  factory PipelineDagNode.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String;
    final type = PipelineDagNodeType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => PipelineDagNodeType.forwardPass,
    );
    return PipelineDagNode(
      id: json['id'] as String,
      type: type,
      customComponentId: json['custom_component_id'] as String?,
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      parameters: (json['parameters'] as Map<String, dynamic>?) ?? const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PipelineDagNode &&
      other.id == id &&
      other.type == type &&
      other.customComponentId == customComponentId &&
      other.x == x &&
      other.y == y &&
      mapEquals(other.parameters, parameters);

  @override
  int get hashCode {
    // Hash parameters by sorting keys for deterministic behavior
    var hash = Object.hash(id, type, customComponentId, x, y);
    final keys = parameters.keys.toList()..sort();
    for (final key in keys) {
      hash = Object.hash(hash, key, parameters[key]);
    }
    return hash;
  }
}

// ── Node footprint ──────────────────────────────────────────────────────────
//
// Every canvas now takes its card footprint from `node_geometry.dart` — the
// pipeline cards used to be 200-wide with fixed 28px port spacing while the
// Architecture cards were 150x132 with proportional spacing, which is what
// made the two surfaces look unrelated. These are the pipeline-side names
// kept so `canvas_provider.dart`'s grid-snap / auto-layout math and the
// canvas widget can never drift apart.

/// Fixed on-canvas width of a pipeline DAG node card.
const double kPipelineDagNodeWidth = kCanvasNodeWidth;
const double kPipelineDagHeaderHeight = kCanvasNodeHeaderHeight;

/// On-canvas footprint of [node]'s card.
Size pipelineDagNodeSize(PipelineDagNode node, {bool compact = false}) =>
    canvasNodeSize(
      inputs: node.type.inputPorts.length,
      outputs: node.type.outputPorts.length,
      compact: compact,
    );

/// On-canvas height of [node]'s card, driven by its port count.
double pipelineDagNodeHeightFor(PipelineDagNode node) =>
    pipelineDagNodeSize(node).height;

// ── Edge ───────────────────────────────────────────────────────────────────

class PipelineDagEdge {
  const PipelineDagEdge({
    required this.id,
    required this.sourceNodeId,
    required this.sourcePort,
    required this.targetNodeId,
    required this.targetPort,
  });

  final String id;
  final String sourceNodeId;
  final String sourcePort;
  final String targetNodeId;
  final String targetPort;

  Map<String, dynamic> toJson() => {
    'id': id,
    'source_node_id': sourceNodeId,
    'source_port': sourcePort,
    'target_node_id': targetNodeId,
    'target_port': targetPort,
  };

  factory PipelineDagEdge.fromJson(Map<String, dynamic> json) =>
      PipelineDagEdge(
        id: json['id'] as String,
        sourceNodeId: json['source_node_id'] as String,
        sourcePort: json['source_port'] as String,
        targetNodeId: json['target_node_id'] as String,
        targetPort: json['target_port'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is PipelineDagEdge &&
      other.id == id &&
      other.sourceNodeId == sourceNodeId &&
      other.sourcePort == sourcePort &&
      other.targetNodeId == targetNodeId &&
      other.targetPort == targetPort;

  @override
  int get hashCode =>
      Object.hash(id, sourceNodeId, sourcePort, targetNodeId, targetPort);
}

// ── DAG ────────────────────────────────────────────────────────────────────

class PipelineDAG {
  const PipelineDAG({this.nodes = const [], this.edges = const []});

  final List<PipelineDagNode> nodes;
  final List<PipelineDagEdge> edges;

  /// Upsert node by id.
  PipelineDAG copyWithNode(PipelineDagNode node) {
    final idx = nodes.indexWhere((n) => n.id == node.id);
    final updated = List<PipelineDagNode>.from(nodes);
    if (idx >= 0) {
      updated[idx] = node;
    } else {
      updated.add(node);
    }
    return PipelineDAG(nodes: updated, edges: edges);
  }

  /// Remove node and all its connected edges.
  PipelineDAG withoutNode(String id) => PipelineDAG(
    nodes: nodes.where((n) => n.id != id).toList(),
    edges: edges
        .where((e) => e.sourceNodeId != id && e.targetNodeId != id)
        .toList(),
  );

  PipelineDAG copyWithEdge(PipelineDagEdge edge) {
    final idx = edges.indexWhere((e) => e.id == edge.id);
    final updated = List<PipelineDagEdge>.from(edges);
    if (idx >= 0) {
      updated[idx] = edge;
    } else {
      updated.add(edge);
    }
    return PipelineDAG(nodes: nodes, edges: updated);
  }

  PipelineDAG withoutEdge(String id) =>
      PipelineDAG(nodes: nodes, edges: edges.where((e) => e.id != id).toList());

  PipelineDAG movedNode(String id, double dx, double dy) {
    final node = nodes.firstWhere((n) => n.id == id);
    return copyWithNode(node.copyWith(x: node.x + dx, y: node.y + dy));
  }

  Map<String, dynamic> toJson() => {
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'edges': edges.map((e) => e.toJson()).toList(),
  };

  factory PipelineDAG.fromJson(Map<String, dynamic> json) => PipelineDAG(
    nodes: (json['nodes'] as List<dynamic>? ?? [])
        .map((n) => PipelineDagNode.fromJson(n as Map<String, dynamic>))
        .toList(),
    edges: (json['edges'] as List<dynamic>? ?? [])
        .map((e) => PipelineDagEdge.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  @override
  bool operator ==(Object other) =>
      other is PipelineDAG &&
      listEquals(other.nodes, nodes) &&
      listEquals(other.edges, edges);

  /// True when this DAG has no nodes (and therefore no meaningful pipeline).
  bool get isEmpty => nodes.isEmpty;

  @override
  int get hashCode => Object.hash(Object.hashAll(nodes), Object.hashAll(edges));
}

// ── Phases ─────────────────────────────────────────────────────────────────

class PipelinePhases {
  const PipelinePhases({
    this.train = const PipelineDAG(),
    this.eval = const PipelineDAG(),
    this.infer = const PipelineDAG(),
  });

  final PipelineDAG train;
  final PipelineDAG eval;
  final PipelineDAG infer;

  PipelineDAG dagFor(PipelinePhaseId phase) => switch (phase) {
    PipelinePhaseId.train => train,
    PipelinePhaseId.eval => eval,
    PipelinePhaseId.infer => infer,
  };

  bool get isEmpty => train.isEmpty && eval.isEmpty && infer.isEmpty;

  PipelinePhases copyWith({
    PipelineDAG? train,
    PipelineDAG? eval,
    PipelineDAG? infer,
  }) => PipelinePhases(
    train: train ?? this.train,
    eval: eval ?? this.eval,
    infer: infer ?? this.infer,
  );

  Map<String, dynamic> toJson() => {
    'train': train.toJson(),
    'eval': eval.toJson(),
    'infer': infer.toJson(),
  };

  factory PipelinePhases.fromJson(Map<String, dynamic> json) => PipelinePhases(
    train: PipelineDAG.fromJson((json['train'] as Map<String, dynamic>?) ?? {}),
    eval: PipelineDAG.fromJson((json['eval'] as Map<String, dynamic>?) ?? {}),
    infer: PipelineDAG.fromJson((json['infer'] as Map<String, dynamic>?) ?? {}),
  );

  @override
  bool operator ==(Object other) =>
      other is PipelinePhases &&
      other.train == train &&
      other.eval == eval &&
      other.infer == infer;

  @override
  int get hashCode => Object.hash(train, eval, infer);
}

// ── Default phase factory ──────────────────────────────────────────────────

/// Build default DAGs based on selected frameworks and dataset.
/// Called once when the user first opens a pipeline tab.
PipelinePhases buildDefaultPhases({
  required List<String> frameworks,
  required String? dataset,
}) {
  final isSnnTorch = frameworks.contains('snntorch_sim');
  final isLava = frameworks.contains('lava') || frameworks.contains('lava_sim');

  if (isSnnTorch) {
    return _buildSnnTorchDefaults();
  } else if (isLava) {
    return _buildLavaDefaults();
  }
  // Generic fallback
  return _buildGenericDefaults();
}

PipelinePhases _buildSnnTorchDefaults() {
  const dx = 240.0;
  const y = 100.0;

  // Train phase: horizontal flow
  const trainNodes = [
    PipelineDagNode(
      id: 'train_dataloader',
      type: PipelineDagNodeType.dataLoader,
      x: 40,
      y: y,
      parameters: {'batch_size': 32, 'shuffle': true},
    ),
    PipelineDagNode(
      id: 'train_statereset',
      type: PipelineDagNodeType.stateReset,
      x: 40 + dx,
      y: y,
    ),
    PipelineDagNode(
      id: 'train_timeloop',
      type: PipelineDagNodeType.timeLoop,
      x: 40 + dx * 2,
      y: y,
      parameters: {'num_steps': 25},
    ),
    PipelineDagNode(
      id: 'train_forward',
      type: PipelineDagNodeType.forwardPass,
      x: 40 + dx * 3,
      y: y,
    ),
    PipelineDagNode(
      id: 'train_loss',
      type: PipelineDagNodeType.mseCountLoss,
      x: 40 + dx * 4,
      y: y,
      parameters: {'correct_rate': 0.8, 'incorrect_rate': 0.2},
    ),
    PipelineDagNode(
      id: 'train_backward',
      type: PipelineDagNodeType.surrogateBackward,
      x: 40 + dx * 5,
      y: y,
    ),
    PipelineDagNode(
      id: 'train_optim',
      type: PipelineDagNodeType.adamOptimiser,
      x: 40 + dx * 6,
      y: y,
      parameters: {'lr': 0.001, 'weight_decay': 0.0},
    ),
    PipelineDagNode(
      id: 'train_logger',
      type: PipelineDagNodeType.lossLogger,
      x: 40 + dx * 7,
      y: y,
    ),
    // Cross-phase edges aren't supported today (train/eval are separate
    // PipelineDAGs), so the train phase gets its own validation-data loader
    // rather than wiring across to the eval phase's testLoader.
    PipelineDagNode(
      id: 'train_valloader',
      type: PipelineDagNodeType.testLoader,
      x: 40 + dx * 7,
      y: y + 180,
      parameters: {'batch_size': 32, 'shuffle': false},
    ),
    PipelineDagNode(
      id: 'train_validationloop',
      type: PipelineDagNodeType.validationLoop,
      x: 40 + dx * 8,
      y: y,
      parameters: {
        'every_n_epochs': 1,
        'save_best_checkpoint': true,
        'checkpoint_metric': 'val_accuracy',
        'checkpoint_mode': 'max',
      },
    ),
  ];
  const trainEdges = [
    PipelineDagEdge(
      id: 'te1',
      sourceNodeId: 'train_dataloader',
      sourcePort: 'data',
      targetNodeId: 'train_forward',
      targetPort: 'input',
    ),
    PipelineDagEdge(
      id: 'te2',
      sourceNodeId: 'train_forward',
      sourcePort: 'spikes',
      targetNodeId: 'train_loss',
      targetPort: 'spikes',
    ),
    PipelineDagEdge(
      id: 'te3',
      sourceNodeId: 'train_loss',
      sourcePort: 'loss',
      targetNodeId: 'train_backward',
      targetPort: 'loss',
    ),
    PipelineDagEdge(
      id: 'te4',
      sourceNodeId: 'train_backward',
      sourcePort: 'gradients',
      targetNodeId: 'train_optim',
      targetPort: 'gradients',
    ),
    PipelineDagEdge(
      id: 'te5',
      sourceNodeId: 'train_loss',
      sourcePort: 'loss',
      targetNodeId: 'train_logger',
      targetPort: 'loss',
    ),
    PipelineDagEdge(
      id: 'te6',
      sourceNodeId: 'train_optim',
      sourcePort: 'model',
      targetNodeId: 'train_validationloop',
      targetPort: 'model',
    ),
    PipelineDagEdge(
      id: 'te7',
      sourceNodeId: 'train_valloader',
      sourcePort: 'data',
      targetNodeId: 'train_validationloop',
      targetPort: 'val_data',
    ),
  ];

  // Eval phase
  const evalNodes = [
    PipelineDagNode(
      id: 'eval_testloader',
      type: PipelineDagNodeType.testLoader,
      x: 40,
      y: y,
      parameters: {'batch_size': 32, 'shuffle': false},
    ),
    PipelineDagNode(
      id: 'eval_statereset',
      type: PipelineDagNodeType.stateReset,
      x: 40 + dx,
      y: y,
    ),
    PipelineDagNode(
      id: 'eval_forward',
      type: PipelineDagNodeType.forwardPass,
      x: 40 + dx * 2,
      y: y,
    ),
    PipelineDagNode(
      id: 'eval_accuracy',
      type: PipelineDagNodeType.accuracyMetric,
      x: 40 + dx * 3,
      y: y,
      parameters: {'top_k': 1},
    ),
  ];
  const evalEdges = [
    PipelineDagEdge(
      id: 'ee1',
      sourceNodeId: 'eval_testloader',
      sourcePort: 'data',
      targetNodeId: 'eval_forward',
      targetPort: 'input',
    ),
    PipelineDagEdge(
      id: 'ee2',
      sourceNodeId: 'eval_forward',
      sourcePort: 'spikes',
      targetNodeId: 'eval_accuracy',
      targetPort: 'spikes',
    ),
    PipelineDagEdge(
      id: 'ee3',
      sourceNodeId: 'eval_testloader',
      sourcePort: 'labels',
      targetNodeId: 'eval_accuracy',
      targetPort: 'labels',
    ),
  ];

  return const PipelinePhases(
    train: PipelineDAG(nodes: trainNodes, edges: trainEdges),
    eval: PipelineDAG(nodes: evalNodes, edges: evalEdges),
  );
}

PipelinePhases _buildLavaDefaults() {
  const dx = 240.0;
  const y = 100.0;
  const trainNodes = [
    PipelineDagNode(
      id: 'lava_dataloader',
      type: PipelineDagNodeType.dataLoader,
      x: 40,
      y: y,
      parameters: {'batch_size': 32, 'shuffle': true},
    ),
    PipelineDagNode(
      id: 'lava_process',
      type: PipelineDagNodeType.lavaProcessGraph,
      x: 40 + dx,
      y: y,
      parameters: {'num_steps': 25},
    ),
    PipelineDagNode(
      id: 'lava_sim',
      type: PipelineDagNodeType.lavaSim,
      x: 40 + dx * 2,
      y: y,
      parameters: {'num_steps': 25, 'backend': 'loihi2sim'},
    ),
  ];
  return PipelinePhases(
    train: const PipelineDAG(nodes: trainNodes, edges: []),
    eval: PipelineDAG(
      nodes: _defaultEvalNodes('lava_eval'),
      edges: _defaultEvalEdges('lava_eval'),
    ),
  );
}

PipelinePhases _buildGenericDefaults() {
  const dx = 240.0;
  const y = 100.0;
  const trainNodes = [
    PipelineDagNode(
      id: 'gen_dataloader',
      type: PipelineDagNodeType.dataLoader,
      x: 40,
      y: y,
      parameters: {'batch_size': 32, 'shuffle': true},
    ),
    PipelineDagNode(
      id: 'gen_forward',
      type: PipelineDagNodeType.forwardPass,
      x: 40 + dx,
      y: y,
    ),
  ];
  return PipelinePhases(
    train: const PipelineDAG(nodes: trainNodes, edges: []),
    eval: PipelineDAG(
      nodes: _defaultEvalNodes('gen_eval'),
      edges: _defaultEvalEdges('gen_eval'),
    ),
  );
}

/// testLoader -> stateReset -> forwardPass -> accuracyMetric, same shape as
/// the snnTorch eval phase. All four node types are framework-generic, so
/// this default works for Lava and the generic fallback too.
List<PipelineDagNode> _defaultEvalNodes(String prefix) {
  const dx = 240.0;
  const y = 100.0;
  return [
    PipelineDagNode(
      id: '${prefix}_testloader',
      type: PipelineDagNodeType.testLoader,
      x: 40,
      y: y,
      parameters: const {'batch_size': 32, 'shuffle': false},
    ),
    PipelineDagNode(
      id: '${prefix}_statereset',
      type: PipelineDagNodeType.stateReset,
      x: 40 + dx,
      y: y,
    ),
    PipelineDagNode(
      id: '${prefix}_forward',
      type: PipelineDagNodeType.forwardPass,
      x: 40 + dx * 2,
      y: y,
    ),
    PipelineDagNode(
      id: '${prefix}_accuracy',
      type: PipelineDagNodeType.accuracyMetric,
      x: 40 + dx * 3,
      y: y,
      parameters: const {'top_k': 1},
    ),
  ];
}

List<PipelineDagEdge> _defaultEvalEdges(String prefix) => [
  PipelineDagEdge(
    id: '${prefix}_e1',
    sourceNodeId: '${prefix}_testloader',
    sourcePort: 'data',
    targetNodeId: '${prefix}_forward',
    targetPort: 'input',
  ),
  PipelineDagEdge(
    id: '${prefix}_e2',
    sourceNodeId: '${prefix}_forward',
    sourcePort: 'spikes',
    targetNodeId: '${prefix}_accuracy',
    targetPort: 'spikes',
  ),
  PipelineDagEdge(
    id: '${prefix}_e3',
    sourceNodeId: '${prefix}_testloader',
    sourcePort: 'labels',
    targetNodeId: '${prefix}_accuracy',
    targetPort: 'labels',
  ),
];
