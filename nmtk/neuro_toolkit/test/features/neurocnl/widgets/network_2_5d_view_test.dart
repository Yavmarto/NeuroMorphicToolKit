// Widget tests for the 2.5D network renderer: it lays out a CanvasGraph with
// the force engine, paints it, reacts to taps (selection), and renders the
// stat/depth/disclosure chrome. animate:false keeps the relax/pulse ticker out
// of the picture so tests are deterministic.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/force_directed_layout.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/network_2_5d_view.dart';

CanvasNode _node(
  String id, {
  String? nirType,
  List<double> position = const [0, 0],
}) {
  return CanvasNode(
    id: id,
    componentId: nirType ?? 'lif_population',
    nirType: nirType,
    label: id,
    parameters: const <String, dynamic>{},
    position: position,
  );
}

CanvasGraph _threeLayerGraph() {
  return CanvasGraph(
    nodes: [
      _node('input', nirType: 'nir.Input', position: const [-240, 0]),
      _node('hidden', position: const [0, 0]),
      _node('output', nirType: 'nir.Output', position: const [240, 0]),
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

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 800, height: 600, child: child)),
    ),
  );
}

/// Recomputes the projected canvas position of [nodeId] exactly the way the
/// widget does, so a tap lands on the node.
Offset _projectedPosition(
  WidgetTester tester,
  CanvasGraph graph, {
  required String nodeId,
}) {
  final size = tester.getSize(find.byType(CustomPaint).first);
  final layout = ForceDirectedLayout(graph, useStoredPositions: true)..relax();
  final box = layout.bounds()!;
  final scale =
      (size.width - 128) / box.width < (size.height - 128) / box.height
      ? ((size.width - 128) / box.width).clamp(0.15, 1.0)
      : ((size.height - 128) / box.height).clamp(0.15, 1.0);
  final target = Offset(size.width / 2, size.height / 2);
  final fitted = target + (layout.positions[nodeId]! - box.center) * scale;
  return Network25DProjection(
    size: size,
  ).project(fitted, layout.depths[nodeId]!);
}

void main() {
  testWidgets('shows an empty state when the graph has no nodes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Network25DView(
          graph: CanvasGraph(nodes: [], edges: [], metadata: {}),
          animate: false,
        ),
      ),
    );
    expect(
      find.text('Add layers to the model to see the network.'),
      findsOneWidget,
    );
  });

  testWidgets('renders a graph with stat chips and a painter', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Network25DView(
          graph: _threeLayerGraph(),
          useStoredPositions: true,
          animate: false,
        ),
      ),
    );

    expect(find.text('3 layers'), findsOneWidget);
    expect(find.text('2 connections'), findsOneWidget);
    expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    expect(find.text('near'), findsOneWidget);
  });

  testWidgets('tapping a node selects it and shows its panel', (
    WidgetTester tester,
  ) async {
    final graph = _threeLayerGraph();
    await tester.pumpWidget(
      _wrap(
        Network25DView(graph: graph, useStoredPositions: true, animate: false),
      ),
    );

    final position = _projectedPosition(tester, graph, nodeId: 'hidden');
    await tester.tapAt(position);
    await tester.pump();

    expect(find.text('hidden'), findsOneWidget);
    expect(find.textContaining('Type: lif_population'), findsOneWidget);

    // Tapping the same node again deselects.
    await tester.tapAt(position);
    await tester.pump();
    expect(find.text('hidden'), findsNothing);
  });

  testWidgets('reports selection through onNodeSelected', (
    WidgetTester tester,
  ) async {
    final graph = _threeLayerGraph();
    final selected = <String?>[];
    await tester.pumpWidget(
      _wrap(
        Network25DView(
          graph: graph,
          useStoredPositions: true,
          animate: false,
          onNodeSelected: (node) => selected.add(node?.id),
        ),
      ),
    );

    await tester.tapAt(_projectedPosition(tester, graph, nodeId: 'input'));
    await tester.pump();
    expect(selected, ['input']);
  });

  testWidgets('renders the co-activation disclosure when strengths exist', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Network25DView(
          graph: _threeLayerGraph(),
          useStoredPositions: true,
          animate: false,
          edgeStrengths: const {'e1': 0.8},
        ),
      ),
    );

    expect(find.textContaining('co-activation'), findsWidgets);
  });

  testWidgets('activity values animate without crashing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Network25DView(
          graph: _threeLayerGraph(),
          useStoredPositions: true,
          animate: true,
          activity: const {'hidden': 0.85},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

  test('Network25DProjection scales nearer nodes larger', () {
    const projection = Network25DProjection(size: Size(800, 600));
    expect(projection.scaleFor(0.0), closeTo(0.6, 0.001));
    expect(projection.scaleFor(1.0), closeTo(1.18, 0.001));
    final near = projection.project(const Offset(400, 300), 1.0);
    final far = projection.project(const Offset(400, 300), 0.0);
    expect(near, isNot(far));
    expect(near.dx, greaterThan(400));
  });
}
