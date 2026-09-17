// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'training_mode_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// When non-null, the canvas architecture view shows a spike-rate colour
/// overlay.  The value is a map from **canvas node id** to spike rate (0–1) —
/// callers resolve backend `layer_spike_rates` keys (a sanitized population
/// name) to node ids via `matchSpikeRatesToNodeIds` before calling
/// [setRates]; entries that couldn't be resolved are already dropped.
///
/// Set to a non-null map by [_RunStep] while training is active; cleared
/// (set to `null`) when the run step is disposed.

@ProviderFor(TrainingMode)
final trainingModeProvider = TrainingModeProvider._();

/// When non-null, the canvas architecture view shows a spike-rate colour
/// overlay.  The value is a map from **canvas node id** to spike rate (0–1) —
/// callers resolve backend `layer_spike_rates` keys (a sanitized population
/// name) to node ids via `matchSpikeRatesToNodeIds` before calling
/// [setRates]; entries that couldn't be resolved are already dropped.
///
/// Set to a non-null map by [_RunStep] while training is active; cleared
/// (set to `null`) when the run step is disposed.
final class TrainingModeProvider
    extends $NotifierProvider<TrainingMode, Map<String, double>?> {
  /// When non-null, the canvas architecture view shows a spike-rate colour
  /// overlay.  The value is a map from **canvas node id** to spike rate (0–1) —
  /// callers resolve backend `layer_spike_rates` keys (a sanitized population
  /// name) to node ids via `matchSpikeRatesToNodeIds` before calling
  /// [setRates]; entries that couldn't be resolved are already dropped.
  ///
  /// Set to a non-null map by [_RunStep] while training is active; cleared
  /// (set to `null`) when the run step is disposed.
  TrainingModeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'trainingModeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$trainingModeHash();

  @$internal
  @override
  TrainingMode create() => TrainingMode();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, double>? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, double>?>(value),
    );
  }
}

String _$trainingModeHash() => r'f66bd1e8c629473cb9fbe5c35b5fcc24f39e4787';

/// When non-null, the canvas architecture view shows a spike-rate colour
/// overlay.  The value is a map from **canvas node id** to spike rate (0–1) —
/// callers resolve backend `layer_spike_rates` keys (a sanitized population
/// name) to node ids via `matchSpikeRatesToNodeIds` before calling
/// [setRates]; entries that couldn't be resolved are already dropped.
///
/// Set to a non-null map by [_RunStep] while training is active; cleared
/// (set to `null`) when the run step is disposed.

abstract class _$TrainingMode extends $Notifier<Map<String, double>?> {
  Map<String, double>? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<Map<String, double>?, Map<String, double>?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, double>?, Map<String, double>?>,
              Map<String, double>?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
