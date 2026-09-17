import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/training_provider.dart';

part 'training_history_provider.g.dart';

/// Stores the per-platform training epoch history for the current run.
///
/// Keyed by platform id (e.g. `'snntorch_sim'`), value is the ordered list of
/// epoch events received over SSE.  Reset to `{}` when a new training run
/// starts.  Consumed by the results step (step 6) for replay.
@riverpod
class TrainingHistory extends _$TrainingHistory {
  @override
  Map<String, List<TrainingEpochEvent>> build() => {};

  void reset() => state = {};

  void update(Map<String, List<TrainingEpochEvent>> value) => state = value;
}
