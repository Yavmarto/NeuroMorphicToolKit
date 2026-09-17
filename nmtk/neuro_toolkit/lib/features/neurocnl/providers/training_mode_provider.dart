import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'training_mode_provider.g.dart';

/// When non-null, the canvas architecture view shows a spike-rate colour
/// overlay.  The value is a map from **canvas node id** to spike rate (0–1) —
/// callers resolve backend `layer_spike_rates` keys (a sanitized population
/// name) to node ids via `matchSpikeRatesToNodeIds` before calling
/// [setRates]; entries that couldn't be resolved are already dropped.
///
/// Set to a non-null map by [_RunStep] while training is active; cleared
/// (set to `null`) when the run step is disposed.
@riverpod
class TrainingMode extends _$TrainingMode {
  bool _mounted = true;

  @override
  Map<String, double>? build() {
    ref.onDispose(() => _mounted = false);
    return null;
  }

  void clear() {
    if (_mounted) {
      state = null;
    }
  }

  /// Clears after Flutter has finished the current widget lifecycle pass.
  /// Riverpod forbids synchronous provider writes from widget disposal.
  void clearDeferred() {
    scheduleMicrotask(clear);
  }

  void setRates(Map<String, double> rates) {
    if (_mounted) {
      state = rates;
    }
  }
}
