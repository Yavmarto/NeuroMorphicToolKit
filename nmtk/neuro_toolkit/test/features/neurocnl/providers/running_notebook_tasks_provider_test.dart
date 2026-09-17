import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/running_notebook_tasks_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

import '../providers_test.mocks.dart';

void main() {
  late MockApiClient mockApi;
  late ProviderContainer container;

  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();

    mockApi = MockApiClient();
    container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(mockApi)],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test(
    'a job-store run is always executing; an idle kernel session is not',
    () async {
      when(mockApi.getActiveNotebookJobs()).thenAnswer(
        (_) async => [
          {'job_id': 'job-1', 'platform': 'snntorch_sim'},
        ],
      );
      when(mockApi.getJupyterSessions()).thenAnswer(
        (_) async => [
          {
            'id': 'session-idle',
            'path': 'notebooks/pipeline_snntorch_sim.ipynb',
            'kernel': {'execution_state': 'idle'},
          },
        ],
      );

      final tasks = await container.read(runningNotebookTasksProvider.future);

      final run = tasks.singleWhere(
        (t) => t.source == RunningNotebookTaskSource.run,
      );
      final session = tasks.singleWhere(
        (t) => t.source == RunningNotebookTaskSource.notebook,
      );
      expect(run.isExecuting, isTrue);
      expect(session.isExecuting, isFalse);
    },
  );

  test('a busy kernel session is executing', () async {
    when(mockApi.getActiveNotebookJobs()).thenAnswer((_) async => []);
    when(mockApi.getJupyterSessions()).thenAnswer(
      (_) async => [
        {
          'id': 'session-busy',
          'path': 'notebooks/pipeline_snntorch_sim.ipynb',
          'kernel': {'execution_state': 'busy'},
        },
      ],
    );

    final tasks = await container.read(runningNotebookTasksProvider.future);

    expect(tasks.single.isExecuting, isTrue);
  });

  test(
    'automatic kernel startup is not treated as notebook execution',
    () async {
      when(mockApi.getActiveNotebookJobs()).thenAnswer((_) async => []);
      when(mockApi.getJupyterSessions()).thenAnswer(
        (_) async => [
          {
            'id': 'session-starting',
            'path': 'notebooks/pipeline_snntorch_sim.ipynb',
            'kernel': {'execution_state': 'starting'},
          },
        ],
      );

      final tasks = await container.read(runningNotebookTasksProvider.future);

      expect(tasks.single.isExecuting, isFalse);
    },
  );

  test(
    'a session with no kernel/execution_state defaults to not executing',
    () async {
      when(mockApi.getActiveNotebookJobs()).thenAnswer((_) async => []);
      when(mockApi.getJupyterSessions()).thenAnswer(
        (_) async => [
          {'id': 'session-no-kernel', 'path': 'notebooks/x.ipynb'},
        ],
      );

      final tasks = await container.read(runningNotebookTasksProvider.future);

      expect(tasks.single.isExecuting, isFalse);
    },
  );
}
