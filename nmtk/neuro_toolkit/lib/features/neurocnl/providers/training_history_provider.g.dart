// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'training_history_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Stores the per-platform training epoch history for the current run.
///
/// Keyed by platform id (e.g. `'snntorch_sim'`), value is the ordered list of
/// epoch events received over SSE.  Reset to `{}` when a new training run
/// starts.  Consumed by the results step (step 6) for replay.

@ProviderFor(TrainingHistory)
final trainingHistoryProvider = TrainingHistoryProvider._();

/// Stores the per-platform training epoch history for the current run.
///
/// Keyed by platform id (e.g. `'snntorch_sim'`), value is the ordered list of
/// epoch events received over SSE.  Reset to `{}` when a new training run
/// starts.  Consumed by the results step (step 6) for replay.
final class TrainingHistoryProvider
    extends
        $NotifierProvider<
          TrainingHistory,
          Map<String, List<TrainingEpochEvent>>
        > {
  /// Stores the per-platform training epoch history for the current run.
  ///
  /// Keyed by platform id (e.g. `'snntorch_sim'`), value is the ordered list of
  /// epoch events received over SSE.  Reset to `{}` when a new training run
  /// starts.  Consumed by the results step (step 6) for replay.
  TrainingHistoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'trainingHistoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$trainingHistoryHash();

  @$internal
  @override
  TrainingHistory create() => TrainingHistory();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, List<TrainingEpochEvent>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<Map<String, List<TrainingEpochEvent>>>(value),
    );
  }
}

String _$trainingHistoryHash() => r'b61961483d0cfff89116c36ca99cffe07f0b2ca8';

/// Stores the per-platform training epoch history for the current run.
///
/// Keyed by platform id (e.g. `'snntorch_sim'`), value is the ordered list of
/// epoch events received over SSE.  Reset to `{}` when a new training run
/// starts.  Consumed by the results step (step 6) for replay.

abstract class _$TrainingHistory
    extends $Notifier<Map<String, List<TrainingEpochEvent>>> {
  Map<String, List<TrainingEpochEvent>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<String, List<TrainingEpochEvent>>,
              Map<String, List<TrainingEpochEvent>>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, List<TrainingEpochEvent>>,
                Map<String, List<TrainingEpochEvent>>
              >,
              Map<String, List<TrainingEpochEvent>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
