// Widget tests for the CEL-141 network-view studio slot (rebuilt on CEL-149):
// NetworkStudioView resolves live `trainingModeProvider` rates and stored
// `PreviewPlayback` review rates into the activity + co-activation inputs the
// provider-free Network25DView consumes, and reports the mode in its header.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/preview.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/nir_types_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/simulation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_mode_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_studio_view.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

CanvasNode _node(String id, {String? nirType}) {
  return CanvasNode(
    id: id,
    componentId: nirType ?? 'lif_population',
    nirType: nirType,
    label: id,
    parameters: const <String, dynamic>{},
    position: const [0, 0],
  );
}

CanvasGraph _graph() {
  return CanvasGraph(
    nodes: [
      _node('input', nirType: 'nir.Input'),
      _node('hidden'),
      _node('output', nirType: 'nir.Output'),
    ],
    edges: [
      CanvasEdge(
        id: 'e1',
        sourceNodeId: 'input',
        sourcePort: 'out',
        targetNodeId: 'hidden',
        targetPort: 'in',
        parameters: const <String, dynamic>{},
      ),
      CanvasEdge(
        id: 'e2',
        sourceNodeId: 'hidden',
        sourcePort: 'out',
        targetNodeId: 'output',
        targetPort: 'in',
        parameters: const <String, dynamic>{},
      ),
    ],
    metadata: const <String, dynamic>{},
  );
}

PreviewPlayback _playback() {
  return const PreviewPlayback(
    durationMs: 500,
    nodes: <PreviewNodePlayback>[
      PreviewNodePlayback(
        nodeId: 'input',
        spikeTrains: <String, List<double>>{
          '0': <double>[0, 50, 100, 150, 200],
        },
      ),
      PreviewNodePlayback(
        nodeId: 'hidden',
        spikeTrains: <String, List<double>>{
          '0': <double>[0, 50, 100, 150, 200],
        },
      ),
    ],
  );
}

ProviderContainer _container({SimulationState? simulation}) {
  return ProviderContainer(
    overrides: [
      canvasProvider.overrideWithValue(CanvasState(graph: _graph())),
      nirNodeTypeMapProvider.overrideWithValue(const <String, NirNodeType>{}),
      if (simulation != null) simulationProvider.overrideWithValue(simulation),
    ],
  );
}

Widget _wrap(ProviderContainer container) {
  return NmtkZetaTheme.wrap(
    builder: (context, light, dark, mode) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: light,
        darkTheme: dark,
        themeMode: mode,
        home: const Scaffold(
          body: SizedBox(width: 800, height: 600, child: NetworkStudioView()),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
  });

  testWidgets(
    'shows the idle header when neither live nor review data exists',
    (WidgetTester tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      expect(find.text('Idle'), findsOneWidget);
      expect(find.text('3 layers'), findsOneWidget);
    },
  );

  testWidgets('shows Live training and drives activity from training rates', (
    WidgetTester tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    container.read(trainingModeProvider.notifier).setRates(
      const <String, double>{'input': 0.9, 'hidden': 0.4},
    );
    await tester.pump();

    expect(find.text('Live training'), findsOneWidget);
    expect(find.text('Idle'), findsNothing);
  });

  testWidgets('seeds review mode from a stored playback with no live rates', (
    WidgetTester tester,
  ) async {
    final container = _container(
      simulation: SimulationState(playback: _playback()),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    expect(find.text('Review playback'), findsOneWidget);
    expect(find.text('Idle'), findsNothing);
  });

  testWidgets('renders the layer search and filters the layer list', (
    WidgetTester tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'outp');
    await tester.pump();

    expect(find.text('output'), findsOneWidget);
    expect(find.text('input'), findsNothing);
    expect(find.text('hidden'), findsNothing);
  });
}
