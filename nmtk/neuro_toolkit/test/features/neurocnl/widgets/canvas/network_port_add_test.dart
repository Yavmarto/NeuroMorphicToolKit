// Widget tests for the Architecture (NIR) canvas port interaction: the port dot
// doubles as the add-node `+` (first tap arms a connection, second tap on the
// same dot opens the palette), plus selecting and deleting an edge.
//
// The canvas body is sized above the compact breakpoint so ports use the
// desktop left/right layout, and the test surface is enlarged to match.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    hide CanvasNode, CanvasEdge;
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_shared_widgets.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_canvas.dart';

class _FakeCanvasApiClient extends ApiClient {
  _FakeCanvasApiClient() : super(baseUrl: 'http://localhost:0');

  @override
  Future<ParseCnlResponse> canvasToCanonical(CanvasGraph graph) async =>
      const ParseCnlResponse(document: CanonicalEditorDocument(irJson: {}));

  @override
  Future<ValidationResult> validateGraph(CanvasGraph graph) async =>
      ValidationResult(valid: true, errors: const []);
}

const String _nodeId = 'lif_1';

ProviderContainer _makeContainer() {
  final container = ProviderContainer(
    overrides: [
      canvas_sync.apiClientProvider.overrideWithValue(_FakeCanvasApiClient()),
    ],
  );
  container
      .read(canvasProvider.notifier)
      .setGraph(
        CanvasGraph(
          nodes: <CanvasNode>[
            CanvasNode(
              id: _nodeId,
              componentId: 'lif_population',
              nirType: 'nir.LIF',
              label: 'LIF',
              parameters: const <String, dynamic>{'name': 'LIF 1'},
              position: const <double>[400, 300],
              width: 200,
              height: 160,
            ),
          ],
          edges: const <CanvasEdge>[],
          metadata: const <String, dynamic>{},
        ),
      );
  return container;
}

Future<void> _pumpCanvas(
  WidgetTester tester,
  ProviderContainer container,
) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 1200, height: 900, child: NetworkCanvas()),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Drains the debounced canonical-doc push and workspace server-sync timers a
/// graph mutation schedules. Without this the framework's pending-timer
/// invariant fails the test even when every assertion has passed.
Future<void> _flushSchedulerTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
}

Finder _port(String portId) =>
    find.byKey(ValueKey<String>('port_${_nodeId}_$portId'));

/// First tap arms the port, second opens the add-node palette.
Future<void> _tapTwice(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
  });

  testWidgets('the port dots are the add buttons — no separate + widget', (
    WidgetTester tester,
  ) async {
    final container = _makeContainer();
    addTearDown(container.dispose);
    await _pumpCanvas(tester, container);

    // nir.LIF has one input and one output, both named by the registry.
    expect(find.byType(CanvasPortWidget), findsNWidgets(2));
    expect(_port('in'), findsOneWidget);
    expect(_port('out'), findsOneWidget);

    await _flushSchedulerTimers(tester);
  });

  testWidgets('one tap on an output arms a connection without opening the '
      'palette', (WidgetTester tester) async {
    final container = _makeContainer();
    addTearDown(container.dispose);
    await _pumpCanvas(tester, container);

    await tester.tap(_port('out'));
    await tester.pumpAndSettle();

    expect(find.text('Pick the input port to wire into.'), findsNothing);
    expect(container.read(canvasProvider).connectingFromNodeId, _nodeId);
    expect(container.read(canvasProvider).connectingFromPortId, 'out');

    await _flushSchedulerTimers(tester);
  });

  testWidgets('a second tap on an output adds a downstream node and wires it', (
    WidgetTester tester,
  ) async {
    final container = _makeContainer();
    addTearDown(container.dispose);
    await _pumpCanvas(tester, container);

    await _tapTwice(tester, _port('out'));

    expect(find.text('Pick the input port to wire into.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('palette_port_nir.Output_in')),
    );
    await tester.pumpAndSettle();

    final CanvasGraph graph = container.read(canvasProvider).graph;
    expect(graph.nodes, hasLength(2));
    expect(graph.edges, hasLength(1));

    final CanvasNode added = graph.nodes.firstWhere(
      (CanvasNode n) => n.id != _nodeId,
    );
    expect(added.nirType, 'nir.Output');

    final CanvasEdge edge = graph.edges.single;
    expect(edge.sourceNodeId, _nodeId);
    expect(edge.sourcePort, 'out');
    expect(edge.targetNodeId, added.id);
    expect(edge.targetPort, 'in');

    await _flushSchedulerTimers(tester);
  });

  testWidgets('one undo reverts the whole add-and-connect', (
    WidgetTester tester,
  ) async {
    final container = _makeContainer();
    addTearDown(container.dispose);
    await _pumpCanvas(tester, container);

    await _tapTwice(tester, _port('out'));
    await tester.tap(
      find.byKey(const ValueKey<String>('palette_port_nir.Output_in')),
    );
    await tester.pumpAndSettle();

    container.read(canvasProvider.notifier).undo();
    await tester.pump();

    final CanvasGraph graph = container.read(canvasProvider).graph;
    expect(graph.nodes.map((CanvasNode n) => n.id), <String>[_nodeId]);
    expect(graph.edges, isEmpty);

    await _flushSchedulerTimers(tester);
  });

  testWidgets('an output-only node type never appears in an output palette', (
    WidgetTester tester,
  ) async {
    final container = _makeContainer();
    addTearDown(container.dispose);
    await _pumpCanvas(tester, container);

    await _tapTwice(tester, _port('out'));

    // nir.Input produces but never consumes, so it cannot receive this wire.
    expect(find.text('Input'), findsNothing);
    expect(find.text('Output'), findsOneWidget);

    await _flushSchedulerTimers(tester);
  });

  group('edge selection and deletion', () {
    /// Builds the wire by hand rather than through the palette, so these tests
    /// fail for edge reasons only.
    Future<ProviderContainer> withEdge(WidgetTester tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      container
          .read(canvasProvider.notifier)
          .setGraph(
            CanvasGraph(
              nodes: <CanvasNode>[
                CanvasNode(
                  id: _nodeId,
                  componentId: 'lif_population',
                  nirType: 'nir.LIF',
                  label: 'LIF',
                  parameters: const <String, dynamic>{'name': 'LIF 1'},
                  position: const <double>[200, 300],
                  width: 200,
                  height: 160,
                ),
                CanvasNode(
                  id: 'out_1',
                  componentId: 'output_node',
                  nirType: 'nir.Output',
                  label: 'Output',
                  parameters: const <String, dynamic>{'name': 'Output 1'},
                  position: const <double>[700, 300],
                  width: 200,
                  height: 160,
                ),
              ],
              edges: <CanvasEdge>[
                CanvasEdge(
                  id: 'edge_1',
                  sourceNodeId: _nodeId,
                  sourcePort: 'out',
                  targetNodeId: 'out_1',
                  targetPort: 'in',
                  parameters: const <String, dynamic>{},
                ),
              ],
              metadata: const <String, dynamic>{},
            ),
          );
      await _pumpCanvas(tester, container);
      return container;
    }

    testWidgets('no ✕ is shown until an edge is selected', (
      WidgetTester tester,
    ) async {
      await withEdge(tester);

      expect(find.byType(CanvasEdgeDeleteButton), findsNothing);

      await _flushSchedulerTimers(tester);
    });

    testWidgets('selecting an edge reveals its ✕, which removes it', (
      WidgetTester tester,
    ) async {
      final container = await withEdge(tester);

      // Selection via the provider: tapping the wire itself is covered by the
      // canvas's existing edge hit-testing, which predates this change.
      container.read(canvasProvider.notifier).selectEdge('edge_1');
      await tester.pumpAndSettle();

      expect(find.byType(CanvasEdgeDeleteButton), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('nir_edge_delete')));
      await tester.pumpAndSettle();

      final CanvasGraph graph = container.read(canvasProvider).graph;
      expect(graph.edges, isEmpty);
      expect(graph.nodes, hasLength(2));
      expect(find.byType(CanvasEdgeDeleteButton), findsNothing);

      await _flushSchedulerTimers(tester);
    });

    testWidgets('the ✕ sits on the wire, between the two ports', (
      WidgetTester tester,
    ) async {
      final container = await withEdge(tester);
      container.read(canvasProvider.notifier).selectEdge('edge_1');
      await tester.pumpAndSettle();

      final Offset centre = tester.getCenter(
        find.byKey(const ValueKey<String>('nir_edge_delete')),
      );
      // Source output port is at x≈400, target input at x≈700+15; the midpoint
      // must land between them rather than on either node.
      expect(centre.dx, greaterThan(400));
      expect(centre.dx, lessThan(720));

      await _flushSchedulerTimers(tester);
    });
  });
}
