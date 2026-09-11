import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_step/results_brainviz_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_mode_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/brainviz_force_3d_view.dart';

CanvasGraph _layerGraph() {
  return CanvasGraph(
    nodes: <CanvasNode>[
      CanvasNode(
        id: 'a',
        componentId: 'lif_population',
        label: 'A',
        parameters: const <String, dynamic>{},
        position: const <double>[0, 0],
      ),
      CanvasNode(
        id: 'b',
        componentId: 'lif_population',
        label: 'B',
        parameters: const <String, dynamic>{},
        position: const <double>[100, 0],
      ),
    ],
    edges: const <CanvasEdge>[],
    metadata: const <String, dynamic>{},
  );
}

Widget _wrap(Widget child, ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 640, height: 480, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('live training feed renders BrainvizForce3DView from canvas graph', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _wrap(
        ResultsBrainvizPanel(
          rasterId: 'empty',
          raster: const <String, List<double>>{},
          duration: 0,
          liveTraining: true,
          onPlaybackComplete: () {},
        ),
        container,
      ),
    );
    await tester.pump();
    container.read(canvasProvider.notifier).setGraph(_layerGraph());
    container.read(trainingModeProvider.notifier).setRates(
      const <String, double>{'a': 0.8, 'b': 0.3},
    );
    await tester.pump();

    expect(find.byType(BrainvizForce3DView), findsOneWidget);
    expect(find.text('Waiting for live training activations…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows waiting copy when liveTraining has no rates yet', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _wrap(
        ResultsBrainvizPanel(
          rasterId: 'empty',
          raster: const <String, List<double>>{},
          duration: 0,
          liveTraining: true,
          onPlaybackComplete: () {},
        ),
        container,
      ),
    );

    expect(find.text('Waiting for live training activations…'), findsOneWidget);
    expect(find.byType(BrainvizForce3DView), findsNothing);
  });

  testWidgets('post-hoc raster path still renders when liveTraining is false', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _wrap(
        ResultsBrainvizPanel(
          rasterId: 'n0',
          raster: <String, List<double>>{
            '0': <double>[10, 50],
            '1': <double>[12, 52],
          },
          duration: 100,
          liveTraining: false,
          onPlaybackComplete: () {},
        ),
        container,
      ),
    );

    expect(find.byType(BrainvizForce3DView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
