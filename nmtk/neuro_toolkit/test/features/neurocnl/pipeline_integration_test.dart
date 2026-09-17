import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/running_notebook_tasks_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/studio_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers_test.mocks.dart';

void main() {
  late MockApiClient mockApi;
  late StreamController<Map<String, dynamic>> events;

  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    RunningNotebookTasksNotifier.debugSetPollInterval(null);
    SharedPreferences.setMockInitialValues({});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
    mockApi = MockApiClient();
    events = StreamController<Map<String, dynamic>>();
    addTearDown(() async {
      if (!events.isClosed) await events.close();
    });

    when(mockApi.getTemplates()).thenAnswer((_) async => const []);
    when(mockApi.getActiveNotebookJobs()).thenAnswer((_) async => const []);
    when(
      mockApi.generateNotebookV2(
        spec: anyNamed('spec'),
        pipelineConfig: anyNamed('pipelineConfig'),
        pipelinePhases: anyNamed('pipelinePhases'),
        pipelineCnl: anyNamed('pipelineCnl'),
        workspacePath: anyNamed('workspacePath'),
        importId: anyNamed('importId'),
      ),
    ).thenAnswer(
      (_) async => const NotebookGenerationResult(
        workspaceFolder: 'interaction-test',
        notebookFilenames: ['pipeline_snntorch_sim.ipynb'],
        generatedAt: 1,
      ),
    );
    when(
      mockApi.runNotebook(
        notebookPath: anyNamed('notebookPath'),
        platform: anyNamed('platform'),
        kernelName: anyNamed('kernelName'),
      ),
    ).thenAnswer((_) async => 'job-1');
    when(
      mockApi.streamTrainingEvents('job-1'),
    ).thenAnswer((_) => events.stream);
  });

  testWidgets('Run SSE completion stays on the live Run canvas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(mockApi)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StudioScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StudioScreen)),
    );
    container.read(workspaceProvider.notifier).setActivePipelineStep('run');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('play-icon')), findsOneWidget);
    expect(find.text('Architecture'), findsOneWidget);
    await tester.tap(find.byKey(const Key('play-icon')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('stop-icon')), findsOneWidget);

    events.add(<String, dynamic>{
      'type': 'epoch',
      'epoch': 1,
      'total_epochs': 2,
      'loss': 0.5,
      'accuracy': 0.7,
      'layer_spike_rates': <String, double>{'lif_1': 0.25},
    });
    events.add(<String, dynamic>{
      'type': 'epoch',
      'epoch': 2,
      'total_epochs': 2,
      'loss': 0.3,
      'accuracy': 0.9,
      'layer_spike_rates': <String, double>{'lif_1': 0.5},
    });
    await tester.pump();
    events.add(<String, dynamic>{'type': 'done'});
    await tester.pumpAndSettle();

    expect(
      container.read(studioResultSessionProvider).phase,
      StudioResultSessionPhase.completed,
    );
    expect(container.read(workspaceProvider).activePipelineStep, 'run');
    expect(
      container.read(studioResultSessionProvider).reviewableSnapshot,
      isNotNull,
    );
    for (final label in const ['Architecture', 'Grid', 'Raster', 'Weights']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Live Metrics'), findsOneWidget);
    expect(find.byKey(const Key('play-icon')), findsOneWidget);

    await tester.tap(find.text('Grid'));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider).activePipelineStep, 'run');
    expect(find.byKey(const Key('play-icon')), findsNothing);
    expect(find.byKey(const Key('studio-result-source-header')), findsNothing);
    expect(find.text('Data'), findsNothing);

    await tester.tap(find.text('Architecture'));
    await tester.pumpAndSettle();
    expect(find.text('Live Metrics'), findsOneWidget);
    expect(find.byKey(const Key('play-icon')), findsOneWidget);
  });
}
