// Widget tests for the pipeline (Train/Eval) canvas port interaction: the port
// dot doubles as the add-node `+` (first tap arms a connection, second tap on
// the same dot opens the palette), and for selecting and deleting an edge.
//
// The canvas body is sized above the 840px compact breakpoint so ports use the
// desktop left/right layout, and the test surface is enlarged to match —
// otherwise taps land outside the 800x600 default surface and hit nothing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    hide CanvasNode;
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/component.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/component_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_shared_widgets.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/pipeline_phase_canvas.dart';

/// Keeps the fire-and-forget canonical-doc/validation sync off the network.
class _FakeCanvasApiClient extends ApiClient {
  _FakeCanvasApiClient() : super(baseUrl: 'http://localhost:0');

  @override
  Future<ParseCnlResponse> canvasToCanonical(CanvasGraph graph) async =>
      const ParseCnlResponse(document: CanonicalEditorDocument(irJson: {}));

  @override
  Future<ValidationResult> validateGraph(CanvasGraph graph) async =>
      ValidationResult(valid: true, errors: const []);
}

const String _nodeId = 'spikeEncoder_1';
const String _upstreamId = 'dataLoader_1';
const String _edgeId = 'edge_1';

ProviderContainer _makeContainer({
  bool withUpstreamEdge = false,
  PipelinePhaseId phase = PipelinePhaseId.train,
}) {
  final container = ProviderContainer(
    overrides: [
      canvas_sync.apiClientProvider.overrideWithValue(_FakeCanvasApiClient()),
      // The palette awaits saved custom components. Unstubbed this reaches for
      // real HTTP and never resolves inside a widget test, so the palette would
      // never open.
      componentsProvider.overrideWith((ref) async => const <ComponentBlock>[]),
    ],
  );
  final notifier = container.read(canvasProvider.notifier);
  notifier.addPipelineDagNode(
    phase,
    const PipelineDagNode(
      id: _nodeId,
      type: PipelineDagNodeType.spikeEncoder,
      x: 200,
      y: 200,
    ),
  );
  if (withUpstreamEdge) {
    notifier.addPipelineDagNode(
      phase,
      const PipelineDagNode(
        id: _upstreamId,
        type: PipelineDagNodeType.dataLoader,
        x: 500,
        y: 200,
      ),
    );
    notifier.addPipelineDagEdge(
      phase,
      const PipelineDagEdge(
        id: _edgeId,
        sourceNodeId: _upstreamId,
        sourcePort: 'data',
        targetNodeId: _nodeId,
        targetPort: 'data',
      ),
    );
  }
  return container;
}

Future<void> _pumpCanvas(
  WidgetTester tester,
  ProviderContainer container, {
  PipelinePhaseId phase = PipelinePhaseId.train,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 900,
            child: PipelinePhaseCanvas(phase: phase),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Riverpod's scheduler posts a zero-duration timer when a provider
/// subscription closes; left unflushed it trips the framework's
/// "timer still pending" invariant and fails an otherwise-passing test.
Future<void> _flushSchedulerTimers(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1));
}

Finder _port(String nodeId, String portId) =>
    find.byKey(ValueKey<String>('port_${nodeId}_$portId'));

PipelineDAG _trainDag(ProviderContainer container) =>
    container.read(canvasProvider).pipelinePhases.dagFor(PipelinePhaseId.train);

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

  group('the port dot is the add-node button', () {
    for (final phase in <PipelinePhaseId>[
      PipelinePhaseId.train,
      PipelinePhaseId.eval,
    ]) {
      testWidgets(
        'workspace restore focuses the first ${phase.name} node safely',
        (tester) async {
          final container = _makeContainer(phase: phase);
          addTearDown(container.dispose);
          await _pumpCanvas(tester, container, phase: phase);

          container
              .read(canvasProvider.notifier)
              .requestWorkspaceRestoreFocus();
          await tester.pump();
          await tester.pump();

          final Finder node = find.byKey(
            const ValueKey<String>('pnode_$_nodeId'),
          );
          expect(tester.getCenter(node), const Offset(216, 252));
          await _flushSchedulerTimers(tester);
        },
      );
    }

    testWidgets('there is no separate floating + widget any more', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      await _pumpCanvas(tester, container);

      // spikeEncoder: one input (`data`), one output (`spikes`) — two dots, and
      // nothing else claiming to be an add button.
      expect(find.byType(CanvasPortWidget), findsNWidgets(2));
      expect(_port(_nodeId, 'data'), findsOneWidget);
      expect(_port(_nodeId, 'spikes'), findsOneWidget);

      await _flushSchedulerTimers(tester);
    });

    testWidgets('one tap on an output arms a connection, it does not open '
        'the palette', (WidgetTester tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      await _pumpCanvas(tester, container);

      await tester.tap(_port(_nodeId, 'spikes'));
      await tester.pumpAndSettle();

      expect(find.text('Pick the input port to wire into.'), findsNothing);
      final CanvasState state = container.read(canvasProvider);
      expect(state.connectingFromNodeId, _nodeId);
      expect(state.connectingFromPortId, 'spikes');

      await _flushSchedulerTimers(tester);
    });

    testWidgets('a second tap on the same output opens the palette', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      await _pumpCanvas(tester, container);

      await tester.tap(_port(_nodeId, 'spikes'));
      await tester.pumpAndSettle();
      await tester.tap(_port(_nodeId, 'spikes'));
      await tester.pumpAndSettle();

      expect(find.text('Pick the input port to wire into.'), findsOneWidget);
      // Data Loader has no inputs, so it can never receive this connection.
      expect(find.text('Data Loader'), findsNothing);
      expect(find.text('Forward Pass'), findsOneWidget);

      await _flushSchedulerTimers(tester);
    });

    testWidgets('picking a port adds exactly one node and one edge, wired '
        'to it', (WidgetTester tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      await _pumpCanvas(tester, container);

      expect(_trainDag(container).nodes, hasLength(1));

      await tester.tap(_port(_nodeId, 'spikes'));
      await tester.pumpAndSettle();
      await tester.tap(_port(_nodeId, 'spikes'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('palette_port_forwardPass_input')),
      );
      await tester.pumpAndSettle();

      final PipelineDAG dag = _trainDag(container);
      expect(dag.nodes, hasLength(2));
      expect(dag.edges, hasLength(1));

      final PipelineDagNode added = dag.nodes.firstWhere(
        (PipelineDagNode n) => n.id != _nodeId,
      );
      expect(added.type, PipelineDagNodeType.forwardPass);

      final PipelineDagEdge edge = dag.edges.single;
      expect(edge.sourceNodeId, _nodeId);
      expect(edge.sourcePort, 'spikes');
      expect(edge.targetNodeId, added.id);
      expect(edge.targetPort, 'input');

      await _flushSchedulerTimers(tester);
    });

    testWidgets('two taps on an input make the new node the edge source', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      await _pumpCanvas(tester, container);

      await tester.tap(_port(_nodeId, 'data'));
      await tester.pumpAndSettle();
      await tester.tap(_port(_nodeId, 'data'));
      await tester.pumpAndSettle();

      expect(find.text('Pick the output port to wire from.'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('palette_port_dataLoader_data')),
      );
      await tester.pumpAndSettle();

      final PipelineDAG dag = _trainDag(container);
      final PipelineDagNode added = dag.nodes.firstWhere(
        (PipelineDagNode n) => n.id != _nodeId,
      );
      expect(added.type, PipelineDagNodeType.dataLoader);

      final PipelineDagEdge edge = dag.edges.single;
      expect(edge.sourceNodeId, added.id);
      expect(edge.sourcePort, 'data');
      expect(edge.targetNodeId, _nodeId);
      expect(edge.targetPort, 'data');

      await _flushSchedulerTimers(tester);
    });

    testWidgets('a tap on empty canvas disarms, so the next tap arms again '
        'rather than opening the palette', (WidgetTester tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      await _pumpCanvas(tester, container);

      await tester.tap(_port(_nodeId, 'spikes'));
      await tester.pumpAndSettle();
      // Far from any node or wire.
      await tester.tapAt(const Offset(1100, 800));
      await tester.pumpAndSettle();

      await tester.tap(_port(_nodeId, 'spikes'));
      await tester.pumpAndSettle();

      expect(find.text('Pick the input port to wire into.'), findsNothing);

      await _flushSchedulerTimers(tester);
    });

    testWidgets('dismissing the palette adds nothing', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      await _pumpCanvas(tester, container);

      await tester.tap(_port(_nodeId, 'spikes'));
      await tester.pumpAndSettle();
      await tester.tap(_port(_nodeId, 'spikes'));
      await tester.pumpAndSettle();

      Navigator.of(tester.element(find.text('Forward Pass'))).pop();
      await tester.pumpAndSettle();

      expect(_trainDag(container).nodes, hasLength(1));
      expect(_trainDag(container).edges, isEmpty);

      await _flushSchedulerTimers(tester);
    });
  });

  group('edge selection and deletion', () {
    /// Scene == viewport here: the canvas starts at identity transform.
    Offset edgeMidpoint(ProviderContainer container) {
      final PipelineDAG dag = _trainDag(container);
      final ends = pipelineEdgeEndpoints(
        dag,
        dag.edges.single,
        isVertical: false,
      )!;
      return pipelineEdgePointAt(ends.start, ends.end, 0.5, isVertical: false);
    }

    testWidgets('no ✕ is shown until an edge is selected', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer(withUpstreamEdge: true);
      addTearDown(container.dispose);
      await _pumpCanvas(tester, container);

      expect(find.byType(CanvasEdgeDeleteButton), findsNothing);

      await _flushSchedulerTimers(tester);
    });

    testWidgets('tapping a wire selects it and reveals its ✕', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer(withUpstreamEdge: true);
      addTearDown(container.dispose);
      await _pumpCanvas(tester, container);

      await tester.tapAt(edgeMidpoint(container));
      await tester.pumpAndSettle();

      expect(container.read(canvasProvider).selectedEdgeId, _edgeId);
      expect(find.byType(CanvasEdgeDeleteButton), findsOneWidget);

      await _flushSchedulerTimers(tester);
    });

    testWidgets('tapping the ✕ removes the edge and leaves the nodes', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer(withUpstreamEdge: true);
      addTearDown(container.dispose);
      await _pumpCanvas(tester, container);

      await tester.tapAt(edgeMidpoint(container));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('pipeline_edge_delete')),
      );
      await tester.pumpAndSettle();

      expect(_trainDag(container).edges, isEmpty);
      expect(_trainDag(container).nodes, hasLength(2));
      expect(find.byType(CanvasEdgeDeleteButton), findsNothing);

      await _flushSchedulerTimers(tester);
    });

    testWidgets('a tap on empty canvas clears the edge selection', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer(withUpstreamEdge: true);
      addTearDown(container.dispose);
      await _pumpCanvas(tester, container);

      await tester.tapAt(edgeMidpoint(container));
      await tester.pumpAndSettle();
      expect(container.read(canvasProvider).selectedEdgeId, _edgeId);

      await tester.tapAt(const Offset(1100, 800));
      await tester.pumpAndSettle();

      expect(container.read(canvasProvider).selectedEdgeId, isNull);
      expect(find.byType(CanvasEdgeDeleteButton), findsNothing);

      await _flushSchedulerTimers(tester);
    });
  });
}
