import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart';
import 'package:neuro_toolkit/features/neurocnl/models/dataset_catalog.dart';
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_pipeline_steps.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/dataset_catalog_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/deploy_results_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/step_unlock_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/workspace_file.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/workflow/snn_workflow_stepper.dart';

void main() {
  test('kStudioPipelineStepNames matches SnnWorkflowPhase enum exactly', () {
    expect(
      kStudioPipelineStepNames,
      equals(SnnWorkflowPhase.values.map((p) => p.name).toList()),
    );
  });

  test('saved Results phases migrate into Run', () {
    // Training results are shown inside the Run step now, so both legacy
    // result-step names land there.
    expect(migrateStepName('deploy'), 'run');
    expect(normalizeStudioPipelineStep('deploy'), 'run');
    expect(migrateStepName('review'), 'run');
    expect(normalizeStudioPipelineStep('review'), 'run');
  });

  test(
    'run and deploy unlock for a ready flat dataset after parse and validate succeed',
    () async {
      const readyFlatDataset = DatasetEntry(
        id: 'flat-dataset',
        label: 'Flat Dataset',
        description: 'Ready dataset',
        storagePath: 'datasets/flat/data.h5',
        status: DatasetServerStatus.ready,
        localPath: '/data/datasets/flat/data.h5',
      );
      const catalog = DatasetCatalogList(
        firebaseAvailable: true,
        datasets: [readyFlatDataset],
      );
      final pipelineState = const PipelineState(
        parseStatus: StepStatus.success,
        validateStatus: StepStatus.success,
        parseResult: ParseResult(sentences: [], total: 1, errors: 0),
        validateResult: ValidationResult(
          layer1: Layer1Result(overall: true, passed: [], failed: []),
          layer2: Layer2Result(
            overall: true,
            checksPassed: [],
            checksFailed: [],
            neuronsFound: [],
          ),
          overall: true,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          datasetCatalogProvider.overrideWith(
            () => _FakeDatasetCatalogNotifier(catalog),
          ),
          pipelineProvider.overrideWith(
            () => _FakePipelineController(pipelineState),
          ),
          workspaceProvider.overrideWith(
            () => _FakeWorkspaceController(
              const WorkspaceState(
                files: [
                  WorkspaceFile(
                    id: 'file-1',
                    name: 'Untitled 1',
                    canonicalDocument: CanonicalEditorDocument(
                      irJson: {},
                      cnlText: 'spec',
                    ),
                  ),
                ],
                activeFileId: 'file-1',
                selectedDataset: 'flat-dataset',
                selectedPlatforms: ['snntorch_sim'],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(datasetCatalogProvider.future);
      final unlocked = container.read(unlockedStepsProvider);

      expect(unlocked.contains('defineModel'), isTrue);
      expect(unlocked.contains('run'), isTrue);
      expect(unlocked.contains('deployHardware'), isTrue);
      // Review is gated on a deploy result, not on a training result.
      expect(unlocked.contains('deployReview'), isFalse);

      container
          .read(studioResultSessionProvider.notifier)
          .restoreSnapshot(
            StudioResultSnapshot(
              id: 'result-1',
              completedAt: DateTime.utc(2026, 8, 11),
              provenance: const StudioResultProvenance(
                workspaceName: 'Workspace',
                modelFingerprint: 'model-1',
              ),
              platforms: const <String, StudioPlatformResult>{},
              selection: const StudioVisualizationSelection(),
              isPartial: false,
            ),
          );
      final afterTrainingResult = container.read(unlockedStepsProvider);
      expect(afterTrainingResult.contains('run'), isTrue);
      expect(afterTrainingResult.contains('deployReview'), isFalse);
    },
  );

  test('a deploy result unlocks Review', () {
    final container = ProviderContainer(
      overrides: [
        datasetCatalogProvider.overrideWith(
          () => _FakeDatasetCatalogNotifier(
            const DatasetCatalogList(firebaseAvailable: true, datasets: []),
          ),
        ),
        pipelineProvider.overrideWith(
          () => _FakePipelineController(const PipelineState()),
        ),
        workspaceProvider.overrideWith(
          () => _FakeWorkspaceController(
            const WorkspaceState(
              files: [
                WorkspaceFile(
                  id: 'file-1',
                  name: 'Untitled 1',
                  canonicalDocument: CanonicalEditorDocument(
                    irJson: {},
                    cnlText: 'spec',
                  ),
                ),
              ],
              activeFileId: 'file-1',
            ),
          ),
        ),
        deployResultsAvailableProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(unlockedStepsProvider).contains('deployReview'),
      isTrue,
    );
  });

  test('only selectData unlocks when no target platform is selected', () {
    final container = ProviderContainer(
      overrides: [
        datasetCatalogProvider.overrideWith(
          () => _FakeDatasetCatalogNotifier(
            const DatasetCatalogList(firebaseAvailable: true, datasets: []),
          ),
        ),
        pipelineProvider.overrideWith(
          () => _FakePipelineController(const PipelineState()),
        ),
        workspaceProvider.overrideWith(
          () => _FakeWorkspaceController(
            const WorkspaceState(
              files: [
                WorkspaceFile(
                  id: 'file-1',
                  name: 'Untitled 1',
                  canonicalDocument: CanonicalEditorDocument(
                    irJson: {},
                    cnlText: 'spec',
                  ),
                ),
              ],
              activeFileId: 'file-1',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final unlocked = container.read(unlockedStepsProvider);

    expect(unlocked, {'selectData'});
  });
}

class _FakeDatasetCatalogNotifier extends DatasetCatalogNotifier {
  _FakeDatasetCatalogNotifier(this._catalog);

  final DatasetCatalogList _catalog;

  @override
  Future<DatasetCatalogList> build() async => _catalog;
}

class _FakePipelineController extends PipelineController {
  _FakePipelineController(this._state);

  final PipelineState _state;

  @override
  PipelineState build() => _state;
}

class _FakeWorkspaceController extends WorkspaceController {
  _FakeWorkspaceController(this._state);

  final WorkspaceState _state;

  @override
  WorkspaceState build() => _state;
}
