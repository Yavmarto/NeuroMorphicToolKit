import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/running_notebook_tasks_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/studio_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers_test.mocks.dart';
import 'golden_path_catalog.dart';

/// Shared Studio UI harness for golden-path verification (CEL-261).
///
/// Loads the same committed `.nmtk` workspaces as `neuro ci golden-paths`,
/// hydrates them through [WorkspaceController.replaceFromWorkspacePayload],
/// drives the Run step via the real [StudioScreen] play control, and asserts
/// on [studioResultSessionProvider] — the same providers the UI renders.
class StudioGoldenPathHarness {
  StudioGoldenPathHarness(this.combo);

  final StudioGoldenPathCombo combo;
  late MockApiClient mockApi;
  late StreamController<Map<String, dynamic>> events;
  ProviderContainer? _container;

  ProviderContainer get container => _container!;

  Future<void> setUp() async {
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
    when(mockApi.getTemplates()).thenAnswer((_) async => const []);
    when(mockApi.getActiveNotebookJobs()).thenAnswer((_) async => const []);
    when(
      mockApi.ensureWorkspace(workspacePath: anyNamed('workspacePath')),
    ).thenAnswer((_) async => 'ok');
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
      (_) async => NotebookGenerationResult(
        workspaceFolder: 'golden-${combo.id}',
        notebookFilenames: ['pipeline_${combo.platformId}.ipynb'],
        generatedAt: 1,
        trainable: combo.expectTrainable,
        notTrainableReason: combo.expectTrainable
            ? ''
            : 'No Studio training adapter for ${combo.platformId}',
      ),
    );
    if (combo.expectTrainable) {
      when(
        mockApi.runNotebook(
          notebookPath: anyNamed('notebookPath'),
          platform: anyNamed('platform'),
          kernelName: anyNamed('kernelName'),
        ),
      ).thenAnswer((_) async => 'job-golden');
      when(
        mockApi.streamTrainingEvents('job-golden'),
      ).thenAnswer((_) => events.stream);
    }
  }

  Future<void> tearDown() async {
    if (!events.isClosed) {
      // Never `await` this close: `StreamController.close()` completes on a
      // microtask in the widget test's fake-async zone, which flutter_test
      // stops draining once the test body returns — awaiting it hangs the
      // whole file (the runner reports "did not complete"). Firing it without
      // awaiting lets the test finish; the process still exits cleanly.
      unawaited(events.close());
    }
    _container?.dispose();
    _container = null;
  }

  Map<String, Object?> loadWorkspacePayload() {
    final path = goldenPathWorkspaceFile(combo);
    final file = File(path);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'golden workspace missing at $path — sync neurocli fixtures',
    );
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  }

  Future<void> pumpStudio(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(mockApi)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              NmtkNotificationCenter(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: StudioScreen()),
        ),
      ),
    );
    // ponytail: bounded pump — pumpAndSettle hangs on Run-step timers.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    _container = ProviderScope.containerOf(
      tester.element(find.byType(StudioScreen)),
    );
    container.read(workspaceProvider.notifier).replaceFromWorkspacePayload(
      loadWorkspacePayload(),
      sourceFileName: combo.workspaceFile,
    );
    expect(
      container.read(workspaceProvider).selectedPlatforms,
      contains(combo.platformId),
    );
    container.read(workspaceProvider.notifier).setActivePipelineStep('run');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> tapPlay(WidgetTester tester) async {
    expect(find.byKey(const Key('play-icon')), findsOneWidget);
    await tester.tap(find.byKey(const Key('play-icon')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> completeTrainableRun(WidgetTester tester) async {
    events.add(<String, dynamic>{'type': 'done'});
    // ponytail: bounded pump — pumpAndSettle hangs on Run-step animations.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  void verifyGenerateCalledWithFramework() {
    final captured = verify(
      mockApi.generateNotebookV2(
        spec: captureAnyNamed('spec'),
        pipelineConfig: captureAnyNamed('pipelineConfig'),
        pipelinePhases: captureAnyNamed('pipelinePhases'),
        pipelineCnl: captureAnyNamed('pipelineCnl'),
        workspacePath: captureAnyNamed('workspacePath'),
        importId: captureAnyNamed('importId'),
      ),
    ).captured;
    final config = captured[1] as Map<String, dynamic>;
    expect(config['framework'], combo.platformId);
  }

  StudioPlatformOutcome platformOutcome() {
    return container
            .read(studioResultSessionProvider)
            .platforms[combo.platformId]
            ?.outcome ??
        StudioPlatformOutcome.idle;
  }
}
