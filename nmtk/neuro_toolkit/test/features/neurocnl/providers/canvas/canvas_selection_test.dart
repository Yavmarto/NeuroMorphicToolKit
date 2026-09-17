import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical_doc;
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://localhost:0');

  @override
  Future<ValidationResult> validateGraph(CanvasGraph graph) async {
    return ValidationResult(valid: true, errors: const []);
  }

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
  ) async {
    return const canonical_doc.ParseCnlResponse(
      document: canonical_doc.CanonicalEditorDocument(irJson: {}, cnlText: ''),
      diagnostics: [],
    );
  }
}

CanvasNode _node(String id, double x, double y) => CanvasNode(
  id: id,
  componentId: 'lif_population',
  nirType: 'nir.LIF',
  label: id,
  parameters: <String, dynamic>{'name': id, 'n_neurons': 4, 'threshold': 1.0},
  position: <double>[x, y],
  metadata: const <String, dynamic>{'category': 'neuron'},
);

ProviderContainer _makeContainer(CanvasGraph graph) {
  final container = ProviderContainer(
    overrides: [
      canvas_sync.apiClientProvider.overrideWithValue(_FakeApiClient()),
    ],
  );
  container.read(canvasProvider.notifier).setGraph(graph);
  return container;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
  });

  group('canvas selection', () {
    test('toggleNodeSelection adds and removes ids with additive mode', () {
      final graph = CanvasGraph(
        nodes: <CanvasNode>[_node('a', 0, 0), _node('b', 200, 0)],
        edges: const <CanvasEdge>[],
        metadata: const <String, dynamic>{},
      );
      final container = _makeContainer(graph);
      addTearDown(container.dispose);

      final notifier = container.read(canvasProvider.notifier);
      notifier.selectNode('a');
      notifier.toggleNodeSelection('b', additive: true);
      expect(container.read(canvasProvider).selectedNodeIds, {'a', 'b'});

      notifier.toggleNodeSelection('a', additive: true);
      expect(container.read(canvasProvider).selectedNodeIds, {'b'});
    });

    test('selectNodesInRect selects intersecting nodes', () {
      final graph = CanvasGraph(
        nodes: <CanvasNode>[
          _node('inside', 50, 50),
          _node('outside', 500, 500),
        ],
        edges: const <CanvasEdge>[],
        metadata: const <String, dynamic>{},
      );
      final container = _makeContainer(graph);
      addTearDown(container.dispose);

      container
          .read(canvasProvider.notifier)
          .selectNodesInRect(const Rect.fromLTWH(0, 0, 180, 180));

      expect(container.read(canvasProvider).selectedNodeIds, {'inside'});
    });

    test('selectAllNodes selects every graph node', () {
      final graph = CanvasGraph(
        nodes: <CanvasNode>[_node('a', 0, 0), _node('b', 100, 100)],
        edges: const <CanvasEdge>[],
        metadata: const <String, dynamic>{},
      );
      final container = _makeContainer(graph);
      addTearDown(container.dispose);

      container.read(canvasProvider.notifier).selectAllNodes();
      expect(container.read(canvasProvider).selectedNodeIds, {'a', 'b'});
    });

    test('deleteSelection removes all selected nodes and attached edges', () {
      final graph = CanvasGraph(
        nodes: <CanvasNode>[_node('a', 0, 0), _node('b', 200, 0)],
        edges: <CanvasEdge>[
          CanvasEdge(
            id: 'edge_ab',
            sourceNodeId: 'a',
            targetNodeId: 'b',
            sourcePort: 'out',
            targetPort: 'in',
            parameters: const <String, dynamic>{},
          ),
        ],
        metadata: const <String, dynamic>{},
      );
      final container = _makeContainer(graph);
      addTearDown(container.dispose);

      final notifier = container.read(canvasProvider.notifier);
      notifier.selectNodes({'a', 'b'});
      notifier.deleteSelection();

      final state = container.read(canvasProvider);
      expect(state.graph.nodes, isEmpty);
      expect(state.graph.edges, isEmpty);
      expect(state.selectedNodeIds, isEmpty);
    });
  });
}
