import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'training_mode_provider.g.dart';

/// When non-null, the canvas architecture view shows a spike-rate colour
/// overlay.  The value is a map from layer/node name to spike rate (0–1).
///
/// Set to a non-null map by [_RunStep] while training is active; cleared
/// (set to `null`) when the run step is disposed.
@riverpod
class TrainingMode extends _$TrainingMode {
  @override
  Map<String, double>? build() => null;

  void clear() => state = null;

  void setRates(Map<String, double> rates) => state = rates;
}
