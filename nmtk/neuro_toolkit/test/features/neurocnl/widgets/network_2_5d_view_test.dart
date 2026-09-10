// Widget tests for the 2.5D network renderer: it lays out a CanvasGraph with
// the globe engine, paints it, reacts to taps (selection), and renders the
// stat/depth/disclosure chrome. animate:false keeps the activity pulse ticker
// out of the picture so tests are deterministic.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/globe_layout.dart';
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
  final layout = GlobeNetworkLayout(graph);
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
      _wrap(Network25DView(graph: _threeLayerGraph(), animate: false)),
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
      _wrap(Network25DView(graph: graph, animate: false)),
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

  group('OrbitCamera', () {
    test('identity is a no-op for the projection', () {
      const camera = OrbitCamera.identity;
      expect(camera.isIdentity, isTrue);

      const projection = Network25DProjection(
        size: Size(800, 600),
        camera: camera,
      );
      final transformed = projection.transformScene(
        const Offset(240, 180),
        0.75,
      );
      expect(transformed.point, const Offset(240, 180));
      expect(transformed.depth, closeTo(0.75, 1e-9));
    });

    test('drag rotates yaw and pitch, and pitch is clamped', () {
      const camera = OrbitCamera.identity;
      final rotated = camera.orbit(50, 0);
      expect(rotated.yaw, greaterThan(0));
      expect(rotated.pitch, 0);

      final tilted = camera.orbit(0, 100000);
      expect(tilted.pitch, OrbitCamera.maxPitch);
      final tiltedBack = camera.orbit(0, -100000);
      expect(tiltedBack.pitch, -OrbitCamera.maxPitch);
    });

    test('zoom clamps to the supported range', () {
      const camera = OrbitCamera.identity;
      expect(camera.zoomBy(2).zoom, closeTo(2.0, 1e-9));
      expect(camera.zoomBy(1000).zoom, OrbitCamera.maxZoom);
      expect(camera.zoomBy(0.0001).zoom, OrbitCamera.minZoom);
      expect(camera.zoomBy(0).zoom, 1.0);
      expect(camera.zoomBy(double.nan).zoom, 1.0);
    });

    test('value equality drives repaint decisions', () {
      expect(const OrbitCamera(), const OrbitCamera());
      expect(
        const OrbitCamera(yaw: 0.2).hashCode,
        const OrbitCamera(yaw: 0.2).hashCode,
      );
      expect(const OrbitCamera(yaw: 0.2), isNot(const OrbitCamera(yaw: 0.3)));
    });

    test('yaw moves an off-axis point through the depth dimension', () {
      const camera = OrbitCamera(yaw: math.pi / 2);
      const projection = Network25DProjection(
        size: Size(800, 600),
        camera: camera,
      );
      // A node 240px right of centre at mid-depth; a 90° yaw should swing it
      // into the depth axis, changing its projected x and depth.
      final rotated = projection.transformScene(const Offset(640, 300), 0.5);
      expect(rotated.point.dx, lessThan(640));
      final projected = projection.project(const Offset(640, 300), 0.5);
      expect(projected, isNot(const Offset(640, 300)));
    });

    test('zoom scales the projected offset from the focal centre', () {
      const center = Offset(400, 300);
      const point = Offset(600, 300);
      const identity = Network25DProjection(size: Size(800, 600));
      const zoomed = Network25DProjection(
        size: Size(800, 600),
        camera: OrbitCamera(zoom: 2.0),
      );
      final base = identity.project(point, 0.5) - center;
      final scaled = zoomed.project(point, 0.5) - center;
      expect(scaled.dx, closeTo(base.dx * 2, 0.001));
      expect(scaled.dy, closeTo(base.dy * 2, 0.001));
    });
  });

  Network25DPainter painterOf(WidgetTester tester) {
    return tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<Network25DPainter>()
        .first;
  }

  testWidgets('dragging empty space orbits the camera without relayout', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(Network25DView(graph: _threeLayerGraph(), animate: false)),
    );
    expect(painterOf(tester).projection.camera.isIdentity, isTrue);

    final orbitGesture = await tester.startGesture(const Offset(400, 200));
    await tester.pump();
    await orbitGesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await orbitGesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await orbitGesture.up();
    await tester.pump();

    final camera = painterOf(tester).projection.camera;
    expect(camera.isIdentity, isFalse);
    expect(camera.yaw, isNot(0.0));

    // The reset affordance appears once the camera has moved.
    expect(find.text('Reset view'), findsOneWidget);
    await tester.tap(find.text('Reset view'));
    await tester.pump();
    expect(painterOf(tester).projection.camera.isIdentity, isTrue);
  });

  testWidgets('scroll wheel zooms the camera', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(Network25DView(graph: _threeLayerGraph(), animate: false)),
    );

    final center = tester.getCenter(find.byType(Network25DView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
    await tester.pump();

    expect(painterOf(tester).projection.camera.zoom, greaterThan(1.0));
  });

  testWidgets('a two-finger pinch zooms the camera', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(Network25DView(graph: _threeLayerGraph(), animate: false)),
    );

    final center = tester.getCenter(find.byType(Network25DView));
    final first = await tester.startGesture(
      center - const Offset(30, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(30, 0),
      pointer: 2,
    );
    await first.moveBy(const Offset(-60, 0));
    await second.moveBy(const Offset(60, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pump();

    expect(painterOf(tester).projection.camera.zoom, greaterThan(1.0));
  });

  testWidgets('paints orbital glow chrome for a populated graph', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Network25DView(
          graph: _threeLayerGraph(),
          activity: const {'input': 0.8, 'hidden': 0.4, 'output': 0.1},
          animate: false,
        ),
      ),
    );

    expect(painterOf(tester).graph.nodes.length, 3);
  });

  testWidgets('cluster indices tint clustered nodes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Network25DView(
          graph: _threeLayerGraph(),
          animate: false,
          nodeClusterIndices: const {'input': 0, 'hidden': 0},
        ),
      ),
    );

    final painter = painterOf(tester);
    expect(painter.nodeClusterIndices?['input'], 0);
    expect(painter.nodeClusterIndices?['output'], isNull);
  });
}
