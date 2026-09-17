import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas_clipboard.dart';
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

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          if (call.method == 'Clipboard.setData' ||
              call.method == 'Clipboard.getData') {
            return null;
          }
          return null;
        });
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
  });

  group('canvas clipboard payload', () {
    test('fromSelection keeps only internal edges', () {
      final graph = CanvasGraph(
        nodes: <CanvasNode>[
          _node('a', 0, 0),
          _node('b', 200, 0),
          _node('c', 400, 0),
        ],
        edges: <CanvasEdge>[
          CanvasEdge(
            id: 'edge_ab',
            sourceNodeId: 'a',
            targetNodeId: 'b',
            sourcePort: 'out',
            targetPort: 'in',
            parameters: const <String, dynamic>{},
          ),
          CanvasEdge(
            id: 'edge_bc',
            sourceNodeId: 'b',
            targetNodeId: 'c',
            sourcePort: 'out',
            targetPort: 'in',
            parameters: const <String, dynamic>{},
          ),
        ],
        metadata: const <String, dynamic>{},
      );

      final payload = CanvasClipboardPayload.fromSelection(
        graph: graph,
        selectedNodeIds: {'a', 'b'},
      );

      expect(payload.nodes.map((CanvasNode n) => n.id), ['a', 'b']);
      expect(payload.edges.map((CanvasEdge e) => e.id), ['edge_ab']);
    });

    test('encode and tryDecode round-trip', () {
      final payload = CanvasClipboardPayload(
        nodes: <CanvasNode>[_node('a', 10, 20)],
        edges: const <CanvasEdge>[],
      );
      final decoded = CanvasClipboardPayload.tryDecode(payload.encode());
      expect(decoded, isNotNull);
      expect(decoded!.nodes.single.id, 'a');
      expect(decoded.nodes.single.position, <double>[10, 20]);
    });
  });

  group('canvas clipboard provider', () {
    test(
      'pasteClipboard remaps ids, offsets positions, and preserves edges',
      () async {
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
        final container = ProviderContainer(
          overrides: [
            canvas_sync.apiClientProvider.overrideWithValue(_FakeApiClient()),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(canvasProvider.notifier);
        notifier.setGraph(graph);
        notifier.selectNodes({'a', 'b'});
        await notifier.copySelection();
        await notifier.pasteClipboard();

        final state = container.read(canvasProvider);
        expect(state.graph.nodes.length, 4);
        expect(state.graph.edges.length, 2);

        final originalIds = {'a', 'b'};
        final pastedNodes = state.graph.nodes
            .where((CanvasNode node) => !originalIds.contains(node.id))
            .toList();
        expect(pastedNodes.length, 2);
        expect(
          pastedNodes.every(
            (CanvasNode node) =>
                node.position[0] >= 40 && node.position[1] >= 40,
          ),
          isTrue,
        );

        final pastedIds = pastedNodes.map((CanvasNode n) => n.id).toSet();
        final pastedEdge = state.graph.edges.firstWhere(
          (CanvasEdge edge) => pastedIds.contains(edge.sourceNodeId),
        );
        expect(pastedIds.contains(pastedEdge.targetNodeId), isTrue);
        expect(state.selectedNodeIds, pastedIds);
      },
    );
  });
}
