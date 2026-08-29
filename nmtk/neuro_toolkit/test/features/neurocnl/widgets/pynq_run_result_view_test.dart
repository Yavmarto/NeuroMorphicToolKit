// What the Review step says about a board run.
//
// Overlay-v2 answers with one word per output neuron per timestep, 1 for a
// spike. The view used to report that stream's *length* as "Output spikes" and
// print it verbatim under "Spiking output neurons", so a run in which nothing
// fired read as "Output spikes: 10" followed by ten zeros — and the explanation
// written for exactly that case never rendered, because an all-zero frame is
// not an empty list.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/dataset_sample.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_pynq_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/studio_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import '../providers_test.mocks.dart';

/// Holds the injected state still.
///
/// The Deploy pane runs a preparation pass on its first frame — validate, then
/// load an evaluation sample — and against a bare mock both fail, which would
/// wipe the very sample these tests are about. Neutering them is what keeps the
/// test about the Review step's rendering.
class _FixedStudioPynqDeployController extends StudioPynqDeployController {
  _FixedStudioPynqDeployController(this._state);

  final StudioPynqDeployState _state;

  @override
  StudioPynqDeployState build() => _state;

  @override
  Future<void> validate(String spec, {String? workspaceFolder}) async {}

  @override
  Future<void> loadDatasetSample(String workspaceFolder, {int? index}) async {}
}

DatasetSample _sample({int? label}) => DatasetSample(
  filename: 'eval_testloader_mnist_val.pt',
  sampleIndex: 3,
  sampleCount: 1000,
  inputWidth: 4,
  inputSpikes: const <int>[1, 0, 1, 0],
  spikeCount: 2,
  label: label,
);

void main() {
  late MockApiClient mockApi;

  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
    mockApi = MockApiClient();
    when(mockApi.getTemplates()).thenAnswer((_) async => const []);
  });

  Future<void> pumpReview(
    WidgetTester tester,
    StudioPynqDeployState state,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          workspaceBootstrapProvider.overrideWithValue(
            const WorkspaceBootstrap(
              initialLocation: '/?panel=deploy&target=pynq',
            ),
          ),
          studioPynqDeployProvider.overrideWith(
            () => _FixedStudioPynqDeployController(state),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StudioScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(StudioScreen)),
    );
    container
        .read(workspaceProvider.notifier)
        .setActivePipelineStep('deployReview');
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('a silent run reports zero spikes and says why', (tester) async {
    // The user's run: ten output neurons, one timestep, nothing fired.
    await pumpReview(
      tester,
      StudioPynqDeployState(
        runResult: PynqRunResult.fromJson(const <String, dynamic>{
          'status': 'success',
          'output_spikes': <int>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
          'timesteps': 1,
          'execution_time_us': 36420.0,
          'output_neurons': 10,
        }),
      ),
    );

    expect(find.text('Output spikes'), findsOneWidget);
    expect(find.text('10'), findsNothing);
    expect(find.text('0'), findsWidgets);
    expect(
      find.textContaining('No output neuron fired'),
      findsOneWidget,
      reason: 'an all-zero frame is not an empty list',
    );
    expect(find.byKey(const Key('pynq-predicted-class')), findsNothing);
  });

  testWidgets('a run of a labelled sample is scored against its label', (
    tester,
  ) async {
    await pumpReview(
      tester,
      StudioPynqDeployState(
        datasetSample: _sample(label: 2),
        runResult: PynqRunResult.fromJson(const <String, dynamic>{
          'status': 'success',
          // Two timesteps of three neurons: neuron 2 fires twice, neuron 0 once.
          'output_spikes': <int>[1, 0, 1, 0, 0, 1],
          'timesteps': 2,
          'execution_time_us': 2000.0,
          'output_neurons': 3,
        }),
      ),
    );

    expect(find.textContaining('Board answered 2'), findsOneWidget);
    expect(find.textContaining('correct'), findsOneWidget);
    expect(find.textContaining('2: 2'), findsOneWidget);
  });

  testWidgets('a wrong answer names the label it was expecting', (
    tester,
  ) async {
    await pumpReview(
      tester,
      StudioPynqDeployState(
        datasetSample: _sample(label: 7),
        runResult: PynqRunResult.fromJson(const <String, dynamic>{
          'status': 'success',
          'output_spikes': <int>[0, 0, 1],
          'timesteps': 1,
          'execution_time_us': 900.0,
          'output_neurons': 3,
        }),
      ),
    );

    expect(
      find.textContaining('Board answered 2 — expected 7'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a kernel that never reported done is not passed off as a result',
    (tester) async {
      await pumpReview(
        tester,
        StudioPynqDeployState(
          runResult: PynqRunResult.fromJson(const <String, dynamic>{
            'status': 'success',
            'output_spikes': <int>[0, 1, 0],
            'timesteps': 1,
            'execution_time_us': 500.0,
            'output_neurons': 3,
            'kernel_reported_done': false,
          }),
        ),
      );

      expect(
        find.textContaining('never reported finishing'),
        findsOneWidget,
        reason: 'the run still comes back status: success',
      );
    },
  );
}
