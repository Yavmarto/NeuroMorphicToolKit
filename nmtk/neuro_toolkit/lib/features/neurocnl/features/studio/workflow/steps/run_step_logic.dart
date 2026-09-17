/// `notApplicable` — the platform's notebook was generated but has no training
/// loop, so Play deliberately did not execute it. Neither success nor failure.
enum TrainingRunOutcome { idle, running, complete, error, notApplicable }

class RunStepLogic {
  /// True when every platform that *could* train did, and at least one did.
  ///
  /// `notApplicable` platforms are ignored rather than counted as failures:
  /// a deploy-only target such as Akida is never run, so requiring it to be
  /// `complete` would leave the success banner permanently hidden whenever one
  /// is selected. It still takes one real success to qualify — a selection of
  /// nothing but deploy-only targets has not succeeded at anything.
  static bool allSucceeded(Map<String, TrainingRunOutcome> status) {
    final trainable = status.values
        .where((s) => s != TrainingRunOutcome.notApplicable)
        .toList(growable: false);
    return trainable.isNotEmpty &&
        trainable.every((s) => s == TrainingRunOutcome.complete);
  }

  static bool hasAnyError(Map<String, TrainingRunOutcome> status) =>
      status.values.any((s) => s == TrainingRunOutcome.error);

  static bool shouldPrepareDatasets({
    required bool keepEditedNotebook,
    required bool cancelled,
  }) => !keepEditedNotebook && !cancelled;
}
