const List<String> kStudioPipelineStepNames = <String>[
  'selectData',
  'defineModel',
  'defineTrain',
  'defineEval',
  'run',
  'deployHardware',
  'deployReview',
];

const String kDefaultStudioPipelineStep = 'selectData';

String? migrateStepName(String? stepName) {
  if (stepName == 'defineArchitecture') return 'defineModel';
  if (stepName == 'trainAndExport') return 'run';
  // The Notebook step was folded into Run — old saved workspaces pointing
  // at it should land on Run instead of falling back to the default step.
  if (stepName == 'trainingSandbox') return 'run';
  // Training results are no longer a step of their own — the Run step shows
  // them in place once a run finishes, so both the old `review` step and the
  // even older `deploy` Results destination land on Run.
  if (stepName == 'review' || stepName == 'deploy') return 'run';
  return stepName;
}

String normalizeStudioPipelineStep(
  String? stepName, {
  String fallback = kDefaultStudioPipelineStep,
}) {
  final migrated = migrateStepName(stepName);
  if (migrated != null && kStudioPipelineStepNames.contains(migrated)) {
    return migrated;
  }
  if (kStudioPipelineStepNames.contains(fallback)) {
    return fallback;
  }
  return kDefaultStudioPipelineStep;
}

int indexOfStudioPipelineStep(
  String? stepName, {
  String fallback = kDefaultStudioPipelineStep,
}) {
  final normalized = normalizeStudioPipelineStep(stepName, fallback: fallback);
  return kStudioPipelineStepNames.indexOf(normalized);
}
