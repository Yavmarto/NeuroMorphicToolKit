import 'package:flutter_riverpod/flutter_riverpod.dart';

// ponytail: record type — no class needed for a two-field tuple
typedef JobRef = ({String jobId, String service});

/// Maps platform id → (jobId, service) for the current run.
/// Training jobs use service='training'; neurosim preview jobs use service='neurosim'.
/// Reset at the start of each new run.
final trainingJobIdsProvider =
    NotifierProvider<_TrainingJobIdsNotifier, Map<String, JobRef>>(
      _TrainingJobIdsNotifier.new,
    );

class _TrainingJobIdsNotifier extends Notifier<Map<String, JobRef>> {
  @override
  Map<String, JobRef> build() => {};

  void reset() => state = {};

  void setJobId(String platform, String jobId, {String service = 'training'}) =>
      state = {...state, platform: (jobId: jobId, service: service)};
}
