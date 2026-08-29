import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'training_provider.g.dart';

/// Training workflow status.
enum TrainingProviderStatus {
  idle,
  loadingCapabilities,
  submitting,
  polling,
  success,
  failure,
}

/// One epoch's worth of progress data, accumulated from the SSE stream.
class TrainingEpochEvent {
  final int epoch;
  final int? totalEpochs;
  final double loss;
  final double? accuracy;
  final double? elapsedSeconds;
  final Map<String, double> layerSpikeRates;
  final List<double> labelProbabilities;
  final String? platform;
  final bool replayed;

  /// Which run phase produced this event: `'train'`, `'val'`, or `'eval'`.
  /// Defaults to `'train'` for events recorded before this field existed.
  final String phase;

  const TrainingEpochEvent({
    required this.epoch,
    required this.loss,
    this.totalEpochs,
    this.accuracy,
    this.elapsedSeconds,
    this.layerSpikeRates = const {},
    this.labelProbabilities = const [],
    this.platform,
    this.replayed = false,
    this.phase = 'train',
  });

  factory TrainingEpochEvent.fromJson(Map<String, dynamic> json) {
    final rawRates = json['layer_spike_rates'] as Map<String, dynamic>? ?? {};
    return TrainingEpochEvent(
      epoch: (json['epoch'] as num).toInt(),
      loss: (json['loss'] as num).toDouble(),
      totalEpochs: (json['total_epochs'] as num?)?.toInt(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      elapsedSeconds: (json['elapsed_seconds'] as num?)?.toDouble(),
      layerSpikeRates: rawRates.map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      ),
      labelProbabilities:
          (json['label_probabilities'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
      platform: json['platform'] as String?,
      replayed: json['replayed'] == true,
      phase: json['phase'] as String? ?? 'train',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'epoch': epoch,
    'total_epochs': totalEpochs,
    'loss': loss,
    'accuracy': accuracy,
    'elapsed_seconds': elapsedSeconds,
    'layer_spike_rates': layerSpikeRates,
    'label_probabilities': labelProbabilities,
    'platform': platform,
    'replayed': replayed,
    'phase': phase,
  };
}

/// State for the training-status plumbing shared by the studio shell.
///
/// The generic-training submission flow this provider used to drive (the
/// now-removed `TrainingInspectorPanel` side panel, `POST /training/run`,
/// `GET /training/capabilities`) has been retired — canvas-DAG training now
/// runs exclusively through pipeline step 5 ("Run", `_RunStep`), which uses
/// `StudioResultSessionController` instead. This class and its state remain
/// because the Studio top bar still reads its legacy status fields, while
/// [TrainingEpochEvent] is the compact event value stored by result snapshots.
class TrainingProviderState {
  final TrainingProviderStatus status;
  final String? jobId;
  final String? errorMessage;
  final List<TrainingEpochEvent> epochs;
  final int epochTick;

  const TrainingProviderState({
    this.status = TrainingProviderStatus.idle,
    this.jobId,
    this.errorMessage,
    this.epochs = const [],
    this.epochTick = 0,
  });

  TrainingProviderState copyWith({
    TrainingProviderStatus? status,
    String? jobId,
    String? errorMessage,
    List<TrainingEpochEvent>? epochs,
    int? epochTick,
    bool clearJob = false,
    bool clearError = false,
    bool clearEpochs = false,
  }) {
    return TrainingProviderState(
      status: status ?? this.status,
      jobId: clearJob ? null : (jobId ?? this.jobId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      epochs: clearEpochs ? const [] : (epochs ?? this.epochs),
      epochTick: epochTick ?? this.epochTick,
    );
  }
}

@riverpod
class TrainingController extends _$TrainingController {
  @override
  TrainingProviderState build() => const TrainingProviderState();

  /// Reset state to idle.
  void reset() {
    state = const TrainingProviderState();
  }
}

/// Backward-compat alias.
final trainingProvider = trainingControllerProvider;
