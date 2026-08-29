import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_pipeline_steps.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/workflow/snn_workflow_stepper.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/dataset_catalog_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/deploy_results_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';

/// Derives the set of step names that the user is allowed to navigate to.
///
/// Steps are unlocked sequentially:
/// - `selectData`   — always unlocked
/// - `defineModel`  — always unlocked (keep reachable from selectData)
/// - Design, Run, and Deploy — unlocked when the current spec has parsed and
///   validated successfully (`architectureValid`)
/// - Review — unlocked only when a deploy target has produced a result. Deploy
///   results are in-memory only, so this re-locks after a restart. Training
///   results no longer unlock a step of their own; the Run step shows them in
///   place.
final unlockedStepsProvider = Provider<Set<String>>((ref) {
  assert(
    kStudioPipelineStepNames.toSet().length == SnnWorkflowPhase.values.length &&
        SnnWorkflowPhase.values.every(
          (p) => kStudioPipelineStepNames.contains(p.name),
        ),
    'kStudioPipelineStepNames is out of sync with SnnWorkflowPhase enum — '
    'update both together',
  );
  // Selects the five fields actually read below rather than watching the whole
  // WorkspaceState. Two reasons: WorkspaceState's freezed `==` is a DeepCollectionEquality
  // walk over every file — including canonicalDocument, pipelineState and the
  // base64 NIR blob — and this provider returns a bare `Set`, which has no
  // `==`, so every recompute notifies unconditionally. Watching the whole state
  // therefore rebuilt StudioScreen and the top bar on every keystroke and every
  // stepper tap.
  final activeStep = ref.watch(
    workspaceProvider.select((w) => w.activePipelineStep),
  );
  final selectedDataset = ref.watch(
    workspaceProvider.select((w) => w.selectedDataset),
  );
  final selectedBenchmarkId = ref.watch(
    workspaceProvider.select((w) => w.selectedBenchmarkId),
  );
  final selectedDeployTarget = ref.watch(
    workspaceProvider.select((w) => w.selectedDeployTarget),
  );
  final selectedPlatforms = ref.watch(
    workspaceProvider.select((w) => w.selectedPlatforms),
  );
  final pipeline = ref.watch(pipelineProvider);
  final hasReviewableResults = ref.watch(
    studioResultSessionProvider.select(
      (session) => session.reviewableSnapshot != null,
    ),
  );
  final catalogAsync = ref.watch(datasetCatalogProvider);
  final catalog = catalogAsync.value;
  final activeStepIndex = indexOfStudioPipelineStep(activeStep);

  final selectedEntry = catalog?.findEntryById(selectedDataset);
  final benchmarkReady = selectedBenchmarkId != null;
  final targetReady = selectedDeployTarget.trim().isNotEmpty;

  final datasetReady =
      selectedDataset != null && selectedEntry?.isReady == true;

  final platformsReady = selectedPlatforms.isNotEmpty;
  final legacySetupReady = !benchmarkReady && datasetReady && platformsReady;
  final benchmarkSetupReady =
      benchmarkReady &&
      targetReady &&
      (selectedDataset == null || datasetReady);
  final legacyWorkspaceCompatibility =
      (!benchmarkReady &&
          selectedDataset == null &&
          selectedPlatforms.isEmpty) ||
      activeStepIndex > 0;

  final architectureValid =
      (legacySetupReady ||
          benchmarkSetupReady ||
          legacyWorkspaceCompatibility) &&
      platformsReady &&
      pipeline.parseStatus == StepStatus.success &&
      (pipeline.parseResult?.errors ?? 0) == 0 &&
      pipeline.validateStatus == StepStatus.success &&
      (pipeline.validateResult?.overall ?? false);

  final unlocked = <String>{
    kStudioPipelineStepNames[0], // selectData always
  };
  if (platformsReady) {
    unlocked.add(kStudioPipelineStepNames[1]); // defineModel — needs a platform
  }
  if (legacyWorkspaceCompatibility && platformsReady) {
    unlocked.addAll(const <String>{
      'defineTrain',
      'defineEval',
      'run',
      'deployHardware',
    });
  }
  if (architectureValid) {
    unlocked.addAll(const <String>{
      'defineTrain',
      'defineEval',
      'run',
      'deployHardware',
    });
  }
  if (hasReviewableResults) {
    // A restored or partial result must always retain a path back to its run
    // status, even if legacy workspace metadata no longer names a platform.
    unlocked.add('run');
  }
  if (ref.watch(deployResultsAvailableProvider)) {
    unlocked.add('deployReview');
  }

  return unlocked;
});

/// Derives the set of SNN workflow step names that are LOCKED (not yet accessible).
/// Convenience inverse of [unlockedStepsProvider].
final lockedPhasesProvider = Provider<Set<String>>((ref) {
  final unlocked = ref.watch(unlockedStepsProvider);
  return kStudioPipelineStepNames.toSet().difference(unlocked);
});
