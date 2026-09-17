import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/notebook_meta_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_job_ids_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_run_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';

import '../providers_test.mocks.dart';

void main() {
  late MockApiClient api;
  late ProviderContainer container;

  setUp(() {
    api = MockApiClient();
    container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    when(
      api.ensureWorkspace(workspacePath: anyNamed('workspacePath')),
    ).thenAnswer((_) async => 'ok');
  });

  group('checkForReattachableJobs', () {
    test('reattaches to a single matching server-side job', () async {
      container.read(workspaceProvider.notifier)
        ..setWorkspaceName('My Workspace')
        ..togglePlatform('snntorch_sim');
      when(api.getActiveNotebookJobs()).thenAnswer(
        (_) async => [
          {
            'job_id': 'job-1',
            'platform': 'snntorch_sim',
            'notebook_path': 'my-workspace/notebook.ipynb',
          },
        ],
      );
      when(
        api.streamTrainingEvents('job-1'),
      ).thenAnswer((_) => const Stream.empty());

      await container
          .read(trainingRunControllerProvider.notifier)
          .checkForReattachableJobs();

      final session = container.read(studioResultSessionProvider);
      expect(session.phase, StudioResultSessionPhase.running);
      expect(
        session.platforms['snntorch_sim']?.outcome,
        StudioPlatformOutcome.running,
      );
      expect(
        container.read(trainingJobIdsProvider)['snntorch_sim']?.jobId,
        'job-1',
      );
      verify(api.streamTrainingEvents('job-1')).called(1);
    });

    test('does nothing when the job list fetch fails', () async {
      container.read(workspaceProvider.notifier).setWorkspaceName('W');
      when(api.getActiveNotebookJobs()).thenThrow(Exception('network down'));

      await container
          .read(trainingRunControllerProvider.notifier)
          .checkForReattachableJobs();

      expect(
        container.read(studioResultSessionProvider).phase,
        StudioResultSessionPhase.idle,
      );
    });

    test('does nothing when no job uniquely matches a platform', () async {
      container.read(workspaceProvider.notifier)
        ..setWorkspaceName('W')
        ..togglePlatform('snntorch_sim');
      when(api.getActiveNotebookJobs()).thenAnswer(
        (_) async => [
          {
            'job_id': 'a',
            'platform': 'snntorch_sim',
            'notebook_path': 'w/a.ipynb',
          },
          {
            'job_id': 'b',
            'platform': 'snntorch_sim',
            'notebook_path': 'w/b.ipynb',
          },
        ],
      );

      await container
          .read(trainingRunControllerProvider.notifier)
          .checkForReattachableJobs();

      expect(
        container.read(studioResultSessionProvider).phase,
        StudioResultSessionPhase.idle,
      );
    });
  });

  group('subscribeToJob / onEvent', () {
    test('epoch events record history; done marks complete', () async {
      container
          .read(studioResultSessionProvider.notifier)
          .beginAttempt(
            platforms: const ['snntorch_sim'],
            provenance: const StudioResultProvenance(
              workspaceName: 'W',
              modelFingerprint: 'fp',
            ),
          );
      final attemptId = container.read(studioResultSessionProvider).attemptId!;
      when(api.streamTrainingEvents('job-1')).thenAnswer(
        (_) => Stream.fromIterable([
          {'type': 'epoch', 'epoch': 1, 'loss': 0.5},
          {'type': 'done'},
        ]),
      );

      container
          .read(trainingRunControllerProvider.notifier)
          .subscribeToJob('snntorch_sim', 'job-1', attemptId);
      await Future<void>.delayed(Duration.zero);

      final session = container.read(studioResultSessionProvider);
      expect(
        session.platforms['snntorch_sim']?.outcome,
        StudioPlatformOutcome.complete,
      );
      expect(session.platforms['snntorch_sim']?.history, hasLength(1));
    });

    test('failed event marks the platform errored', () async {
      container
          .read(studioResultSessionProvider.notifier)
          .beginAttempt(
            platforms: const ['snntorch_sim'],
            provenance: const StudioResultProvenance(
              workspaceName: 'W',
              modelFingerprint: 'fp',
            ),
          );
      final attemptId = container.read(studioResultSessionProvider).attemptId!;
      when(api.streamTrainingEvents('job-1')).thenAnswer(
        (_) => Stream.fromIterable([
          {'type': 'failed', 'error': 'boom'},
        ]),
      );

      container
          .read(trainingRunControllerProvider.notifier)
          .subscribeToJob('snntorch_sim', 'job-1', attemptId);
      await Future<void>.delayed(Duration.zero);

      final session = container.read(studioResultSessionProvider);
      expect(
        session.platforms['snntorch_sim']?.outcome,
        StudioPlatformOutcome.error,
      );
    });

    test('a superseded attempt is ignored', () async {
      container
          .read(studioResultSessionProvider.notifier)
          .beginAttempt(
            platforms: const ['snntorch_sim'],
            provenance: const StudioResultProvenance(
              workspaceName: 'W',
              modelFingerprint: 'fp',
            ),
          );
      const staleAttemptId = 'stale-attempt';
      when(api.streamTrainingEvents('job-1')).thenAnswer(
        (_) => Stream.fromIterable([
          {'type': 'done'},
        ]),
      );

      container
          .read(trainingRunControllerProvider.notifier)
          .subscribeToJob('snntorch_sim', 'job-1', staleAttemptId);
      await Future<void>.delayed(Duration.zero);

      expect(
        container
            .read(studioResultSessionProvider)
            .platforms['snntorch_sim']
            ?.outcome,
        StudioPlatformOutcome.running,
      );
    });
  });

  group('hasExecutingManualSession', () {
    test('true when a matching session is busy', () async {
      when(api.getJupyterSessions()).thenAnswer(
        (_) async => [
          {
            'path': 'w/notebook.ipynb',
            'kernel': {'execution_state': 'busy'},
          },
        ],
      );

      final result = await container
          .read(trainingRunControllerProvider.notifier)
          .hasExecutingManualSession(api, 'w/notebook.ipynb');

      expect(result, isTrue);
    });

    test('false when no session matches', () async {
      when(api.getJupyterSessions()).thenAnswer((_) async => []);

      final result = await container
          .read(trainingRunControllerProvider.notifier)
          .hasExecutingManualSession(api, 'w/notebook.ipynb');

      expect(result, isFalse);
    });

    test('fails open (false) when the check throws', () async {
      when(api.getJupyterSessions()).thenThrow(Exception('down'));

      final result = await container
          .read(trainingRunControllerProvider.notifier)
          .hasExecutingManualSession(api, 'w/notebook.ipynb');

      expect(result, isFalse);
    });
  });

  group('checkForEditedNotebook', () {
    test(
      'returns null and never confirms when there is no generation record',
      () async {
        var confirmCalls = 0;
        final result = await container
            .read(trainingRunControllerProvider.notifier)
            .checkForEditedNotebook(
              api,
              'snntorch_sim',
              confirmEditChoice: () async {
                confirmCalls++;
                return NotebookEditChoice.keepEdits;
              },
            );

        expect(result, isNull);
        expect(confirmCalls, 0);
      },
    );

    test(
      'asks for a choice and returns it when the notebook was edited',
      () async {
        container
            .read(notebookMetaProvider.notifier)
            .recordGeneration(
              'snntorch_sim',
              const NotebookGenerationMeta(
                workspaceFolder: 'w',
                filename: 'n.ipynb',
                generatedAt: 100,
              ),
            );
        when(
          api.getNotebookLastModified(
            workspaceFolder: 'w',
            filename: 'n.ipynb',
          ),
        ).thenAnswer((_) async => 200);

        final result = await container
            .read(trainingRunControllerProvider.notifier)
            .checkForEditedNotebook(
              api,
              'snntorch_sim',
              confirmEditChoice: () async =>
                  NotebookEditChoice.discardAndRegenerate,
            );

        expect(result, NotebookEditChoice.discardAndRegenerate);
      },
    );
  });

  group('startTraining', () {
    test(
      'begins a fresh attempt and returns the resolved platform list',
      () async {
        when(
          api.generateNotebookV2(
            spec: anyNamed('spec'),
            pipelineConfig: anyNamed('pipelineConfig'),
            pipelinePhases: anyNamed('pipelinePhases'),
            workspacePath: anyNamed('workspacePath'),
            importId: anyNamed('importId'),
          ),
        ).thenAnswer(
          (_) async => const NotebookGenerationResult(
            workspaceFolder: 'w',
            notebookFilenames: ['n.ipynb'],
            trainable: false,
            notTrainableReason: 'deploy-only target',
          ),
        );

        final platforms = await container
            .read(trainingRunControllerProvider.notifier)
            .startTraining(
              confirmEditChoice: () async => NotebookEditChoice.cancelled,
              confirmStopManualSession: () async => true,
            );

        expect(platforms, ['snntorch_sim']);
        expect(
          container.read(studioResultSessionProvider).phase,
          StudioResultSessionPhase.running,
        );
      },
    );
  });

  group('stopTraining / cancelSubscriptions', () {
    test('stopTraining cancels running platforms', () async {
      container
          .read(studioResultSessionProvider.notifier)
          .beginAttempt(
            platforms: const ['snntorch_sim'],
            provenance: const StudioResultProvenance(
              workspaceName: 'W',
              modelFingerprint: 'fp',
            ),
          );

      container.read(trainingRunControllerProvider.notifier).stopTraining();

      expect(
        container
            .read(studioResultSessionProvider)
            .platforms['snntorch_sim']
            ?.outcome,
        StudioPlatformOutcome.cancelled,
      );
    });
  });
}
