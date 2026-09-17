import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/simulator.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/simulator/signals_tab.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

SimulatorRunResult _result({
  SimulatorStimulusRecord? stimulus,
  TrainedWeightStatus? trainedWeights,
  Map<String, Map<String, List<int>>> spikes = const {},
  Map<String, dynamic> metadata = const {'dt_ms': 1.0},
}) {
  return SimulatorRunResult(
    backendName: 'snntorch_sim',
    status: SimulatorStatus.completed,
    supportLevel: SupportLevel.exact,
    timesteps: 100,
    durationSeconds: 0.25,
    spikes: spikes,
    nirSummary: const SimulatorNIRSummary(nodeCount: 3, edgeCount: 2),
    stimulus: stimulus,
    trainedWeights: trainedWeights,
    metadata: metadata,
  );
}

Future<void> _pump(WidgetTester tester, SimulatorRunResult result) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: SimulatorSignalsTab(result: result)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
  });

  testWidgets(
    'says the run captured no input rather than showing a blank box',
    (tester) async {
      await _pump(tester, _result());
      expect(find.textContaining('did not record its input'), findsOneWidget);
    },
  );

  testWidgets('shows nothing sourced from a run other than this one', (
    tester,
  ) async {
    // A layer-to-layer flow panel used to live here, fed by the canvas's Nengo
    // preview — a different engine on a different run. Side by side with this
    // backend's raster it implied the two matched. Every panel must come from
    // the run being shown.
    await _pump(tester, _result());
    expect(find.textContaining('Architecture canvas'), findsNothing);
    expect(find.text('Signal flow'), findsNothing);
  });

  testWidgets('names the zero weights as the reason nothing fired', (
    tester,
  ) async {
    await _pump(tester, _result());
    expect(
      find.textContaining('No trained weights were loaded'),
      findsOneWidget,
    );
  });

  testWidgets('shows the input population and its rate beside the output', (
    tester,
  ) async {
    await _pump(
      tester,
      _result(
        stimulus: SimulatorStimulusRecord(
          population: 'input',
          neuronCount: 4,
          spikes: {'0': List<int>.generate(10, (i) => i)},
        ),
        spikes: {
          'output': {
            '0': const [5, 6],
          },
        },
      ),
    );

    expect(find.textContaining('input (input)'), findsOneWidget);
    expect(find.text('output'), findsOneWidget);
    // 10 spikes over 4 neurons across 100 ms.
    expect(find.textContaining('25.0 Hz'), findsOneWidget);
  });

  testWidgets('says when the input was capped for transport', (tester) async {
    await _pump(
      tester,
      _result(
        stimulus: const SimulatorStimulusRecord(
          population: 'input',
          neuronCount: 800,
          truncated: true,
          spikes: {
            '0': [1, 2],
          },
        ),
      ),
    );
    expect(find.textContaining('Capped for transport'), findsOneWidget);
  });

  testWidgets('shows one density bar per weight layer', (tester) async {
    await _pump(
      tester,
      _result(
        trainedWeights: const TrainedWeightStatus(
          applied: true,
          detail: 'Loaded trained weights from fc1, fc2.',
          nonzero: 300,
          shape: [10, 10],
          layers: [
            TrainedWeightLayer(name: 'fc1', shape: [10, 10], nonzero: 50),
            TrainedWeightLayer(name: 'fc2', shape: [10, 25], nonzero: 250),
          ],
        ),
      ),
    );

    expect(find.text('fc1'), findsOneWidget);
    expect(find.text('fc2'), findsOneWidget);
    expect(find.textContaining('50.0% filled'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
  });

  testWidgets(
    'falls back to the single total when the backend sends no breakdown',
    (tester) async {
      await _pump(
        tester,
        _result(
          trainedWeights: const TrainedWeightStatus(
            applied: true,
            detail: 'Loaded trained weights from fc1.',
            sourceNode: 'fc1',
            nonzero: 40,
            shape: [10, 10],
          ),
        ),
      );

      expect(find.text('fc1'), findsOneWidget);
      expect(find.textContaining('40.0% filled'), findsOneWidget);
    },
  );
}
