import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical_doc;
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/grid.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://localhost:0');

  @override
  Future<ValidationResult> validateGraph(CanvasGraph graph) async =>
      ValidationResult(valid: true, errors: const []);

  @override
  Future<String> generateCnl(CanvasGraph graph) async => '';

  @override
  Future<CanvasGraph> repairCnl(String cnl, {CanvasGraph? graph}) async =>
      graph ??
      CanvasGraph(nodes: const [], edges: const [], metadata: const {});

  @override
  Future<ImportNirBytesResponse> importNirBytes(Uint8List payload) async =>
      ImportNirBytesResponse(
        graph: CanvasGraph(
          nodes: const [],
          edges: const [],
          metadata: const {},
        ),
      );

  @override
  Future<Uint8List> exportNirBytes(CanvasGraph graph) async => Uint8List(0);

  @override
  Future<String> generateCnlFromNirBytes(Uint8List payload) async => '';

  @override
  Future<canonical_doc.ParseCnlResponse> canvasToCanonical(
    CanvasGraph graph,
  ) async => const canonical_doc.ParseCnlResponse(
    document: canonical_doc.CanonicalEditorDocument(irJson: {}, cnlText: ''),
    diagnostics: [],
  );
}

CanvasNode _node(String id, double x, double y) => CanvasNode(
  id: id,
  componentId: 'lif_population',
  nirType: 'nir.LIF',
  label: id,
  parameters: <String, dynamic>{'name': id, 'n_neurons': 4, 'threshold': 1.0},
  position: <double>[x, y],
  width: 200,
  height: 160,
  metadata: const <String, dynamic>{'category': 'neuron'},
);

ProviderContainer _makeContainer() {
  final container = ProviderContainer(
    overrides: [
      canvas_sync.apiClientProvider.overrideWithValue(_FakeApiClient()),
    ],
  );
  return container;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
  });

  group('addNode grid snapping', () {
    test('snaps a raw drop position to its nearest cell origin', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(canvasProvider.notifier);

      notifier.addNode(_node('a', kGridCellWidth * 2.1, 5));

      final node = container.read(canvasProvider).graph.nodes.single;
      expect(node.position, <double>[
        gridCoordToCenteredOffset(
          const GridCoord(2, 0),
          nodeWidth: node.width,
          nodeHeight: node.height,
        ).dx,
        16.0,
      ]);
    });

    test('centers the node inside the snapped grid cell', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(canvasProvider.notifier);

      notifier.addNode(_node('a', 0, 0));

      final node = container.read(canvasProvider).graph.nodes.single;
      expect(node.position, <double>[20.0, 16.0]);
    });

    test('resolves a collision to a different, free cell', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(canvasProvider.notifier);

      notifier.addNode(_node('a', 0, 0));
      notifier.addNode(_node('b', 5, 5)); // same target cell as 'a'

      final nodes = container.read(canvasProvider).graph.nodes;
      final positions = nodes.map((CanvasNode n) => n.position).toSet();
      expect(
        positions.length,
        2,
        reason: 'no two nodes may occupy the same grid cell',
      );
      expect(nodes.first.position, <double>[20.0, 16.0]);
      expect(nodes.last.position, isNot(<double>[20.0, 16.0]));
    });
  });

  group('addNode reference-node placement', () {
    test('places the new node to the right of the selected node', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(canvasProvider.notifier);

      notifier.addNode(_node('a', 0, 0)); // lands on (0,0), auto-selected
      notifier.addNode(_node('b', 999, 999), preferRight: true);

      final b = container
          .read(canvasProvider)
          .graph
          .nodes
          .firstWhere((CanvasNode n) => n.id == 'b');
      expect(b.position, <double>[
        gridCoordToCenteredOffset(
          const GridCoord(1, 0),
          nodeWidth: b.width,
          nodeHeight: b.height,
        ).dx,
        16.0,
      ]);
    });

    test('places the new node below the selected node when preferRight is '
        'false', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(canvasProvider.notifier);

      notifier.addNode(_node('a', 0, 0));
      notifier.addNode(_node('b', 999, 999), preferRight: false);

      final b = container
          .read(canvasProvider)
          .graph
          .nodes
          .firstWhere((CanvasNode n) => n.id == 'b');
      expect(b.position, <double>[
        20.0,
        gridCoordToCenteredOffset(
          const GridCoord(0, 1),
          nodeWidth: b.width,
          nodeHeight: b.height,
        ).dy,
      ]);
    });

    test('falls back to the most recently added node once selection is '
        'cleared', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(canvasProvider.notifier);

      notifier.addNode(_node('a', 0, 0)); // cell (0,0)
      notifier.addNode(_node('b', 999, 999)); // right of a -> cell (1,0)
      notifier.clearSelection();
      notifier.addNode(_node('c', 999, 999)); // right of b -> cell (2,0)

      final c = container
          .read(canvasProvider)
          .graph
          .nodes
          .firstWhere((CanvasNode n) => n.id == 'c');
      expect(c.position, <double>[
        gridCoordToCenteredOffset(
          const GridCoord(2, 0),
          nodeWidth: c.width,
          nodeHeight: c.height,
        ).dx,
        16.0,
      ]);
    });
  });

  group('addPipelineDagNode reference-node placement', () {
    test('places the new node to the right of the selected DAG node', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(canvasProvider.notifier);

      notifier.addPipelineDagNode(
        PipelinePhaseId.train,
        const PipelineDagNode(id: 'x', type: PipelineDagNodeType.dataLoader),
      );
      notifier.addPipelineDagNode(
        PipelinePhaseId.train,
        const PipelineDagNode(id: 'y', type: PipelineDagNodeType.dataLoader),
        preferRight: true,
      );

      final dag = container
          .read(canvasProvider)
          .pipelinePhases
          .dagFor(PipelinePhaseId.train);
      final x = dag.nodes.firstWhere((n) => n.id == 'x');
      final y = dag.nodes.firstWhere((n) => n.id == 'y');
      expect(y.x, greaterThan(x.x));
      expect(y.y, x.y);
      expect(
        container.read(canvasProvider).selectedNodeIds,
        <String>{'y'},
        reason: 'adding a node selects it, matching addNode',
      );
    });
  });

  group('loaded graph grid snapping', () {
    test('setGraph snaps imported file nodes onto centered grid cells', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(canvasProvider.notifier);

      notifier.setGraph(
        CanvasGraph(
          nodes: [_node('a', 0, 0), _node('b', 2, 2)],
          edges: const [],
          metadata: const {},
        ),
      );

      final nodes = container.read(canvasProvider).graph.nodes;
      expect(nodes.first.position, <double>[20.0, 16.0]);
      expect(nodes.last.position, isNot(<double>[20.0, 16.0]));
    });
  });

  group('snapNodeToGrid (drag release)', () {
    test('snaps a live-dragged position onto the nearest free cell', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(canvasProvider.notifier);

      notifier.addNode(_node('a', 0, 0));
      // Simulate a live drag (unsnapped) landing near cell (1, 0).
      notifier.updateNodePosition('a', kGridCellWidth * 0.95, 3);
      notifier.snapNodeToGrid('a');

      final node = container
          .read(canvasProvider)
          .graph
          .nodes
          .firstWhere((CanvasNode n) => n.id == 'a');
      expect(node.position, <double>[kGridCellWidth + 20.0, 16.0]);
    });

    test('dragging a node back onto its own cell is a no-op', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(canvasProvider.notifier);

      notifier.addNode(_node('a', 0, 0));
      notifier.updateNodePosition('a', 3, 4); // small jitter, same cell
      notifier.snapNodeToGrid('a');

      final node = container
          .read(canvasProvider)
          .graph
          .nodes
          .firstWhere((CanvasNode n) => n.id == 'a');
      expect(node.position, <double>[20.0, 16.0]);
    });

    test('never lands a dragged node on top of another node', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(canvasProvider.notifier);

      notifier.addNode(_node('a', 0, 0));
      notifier.addNode(_node('b', kGridCellWidth, 0));

      // Drag 'b' so its live position lands exactly on top of 'a'.
      notifier.updateNodePosition('b', 0, 0);
      notifier.snapNodeToGrid('b');

      final nodes = container.read(canvasProvider).graph.nodes;
      final a = nodes.firstWhere((CanvasNode n) => n.id == 'a');
      final b = nodes.firstWhere((CanvasNode n) => n.id == 'b');
      expect(a.position, isNot(b.position));
    });
  });
}
