// Node layout (position/size/visibility) preservation across canonical mirrors.
//
// Bug: canvasGraphFromCanonical never carries width/height/isVisible forward
// from the existing node (the canonical document has no such fields), so
// any mirror of an externally-changed canonical doc — not just this node's
// own edit — would silently reset every node's size/visibility to model
// defaults (width: 150.0, height: 132.0, isVisible: true). Position survives
// mid-session mirrors already (canvasGraphFromCanonical does forward it),
// but not a cold reload where there is no existing graph to inherit from.
//
// Fix: CanvasController._layoutOverrides records the live layout on every
// UI-local mutation and re-applies it after every _mirrorProjection.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical_doc;
import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

class _TrackingApiClient extends ApiClient {
  _TrackingApiClient() : super(baseUrl: 'http://localhost:0');

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
  ) async {
    // Echo the input graph's nodes back as a canvas projection — same
    // pattern as canvas_provider_dopush_preservation_test.dart.
    return canonical_doc.ParseCnlResponse(
      document: canonical_doc.CanonicalEditorDocument(
        irJson: const {},
        cnlText: '',
        canvas: canonical_doc.CanvasProjection(
          nodes: graph.nodes
              .map((n) => canonical_doc.CanvasNode(id: n.id, label: n.id))
              .toList(),
          edges: const [],
        ),
      ),
      diagnostics: const [],
    );
  }

  @override
  Future<canonical_doc.ParseCnlResponse> parseCnlCanonical(
    String specText,
  ) async {
    return canonical_doc.ParseCnlResponse(
      document: canonical_doc.CanonicalEditorDocument(
        irJson: const {},
        cnlText: specText,
      ),
      diagnostics: const [],
    );
  }
}

class _NoOpPipelineController extends PipelineController {
  _NoOpPipelineController(this._initialState);
  final PipelineState _initialState;

  @override
  PipelineState build() => _initialState;

  @override
  Future<void> runParseAndValidate(
    String spec, {
    String? backendOverride,
  }) async {}
}

CanvasNode _lifNode({String id = 'lif_0'}) => CanvasNode(
  id: id,
  componentId: 'lif_population',
  nirType: 'nir.LIF',
  label: 'LIF',
  parameters: <String, dynamic>{'name': id, 'n_neurons': 10},
  position: const <double>[100.0, 100.0],
  metadata: const <String, dynamic>{'category': 'neuron'},
);

({ProviderContainer container, _TrackingApiClient client}) _makeContainer() {
  final client = _TrackingApiClient();
  final container = ProviderContainer(
    overrides: <Override>[
      canvas_sync.apiClientProvider.overrideWithValue(client),
      pipelineProvider.overrideWith(
        () => _NoOpPipelineController(const PipelineState()),
      ),
    ],
  );
  return (container: container, client: client);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
  });

  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
  });

  test(
    'width/height/isVisible survive an externally-triggered canonical mirror',
    () async {
      final (:container, :client) = _makeContainer();
      addTearDown(container.dispose);
      container.listen(canvasProvider, (_, _) {});

      container.read(canvasProvider.notifier).addNode(_lifNode());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      container
          .read(canvasProvider.notifier)
          .updateNodeSize('lif_0', 300.0, 250.0);
      container.read(canvasProvider.notifier).toggleNodeVisibility('lif_0');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final beforeMirror = container
          .read(canvasProvider)
          .graph
          .nodes
          .firstWhere((CanvasNode n) => n.id == 'lif_0');
      expect(beforeMirror.width, 300.0);
      expect(beforeMirror.height, 250.0);
      expect(beforeMirror.isVisible, isFalse);

      // Simulate an external canonical write NOT originating from this
      // node's own push (e.g. a NIR re-import or template load) — call the
      // canonical controller directly rather than through
      // CanvasController._doPush, so CanvasController's `_pendingPushes`
      // guard is false and the resulting canonicalDocProvider change is
      // treated as external, exactly like the real bug scenario.
      await container
          .read(canonicalDocControllerProvider.notifier)
          .updateFromCanvas(container.read(canvasProvider).graph);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final afterMirror = container
          .read(canvasProvider)
          .graph
          .nodes
          .firstWhere((CanvasNode n) => n.id == 'lif_0');
      expect(
        afterMirror.width,
        300.0,
        reason:
            'width must survive an external canonical mirror, not reset to '
            'the CanvasNode default (150.0).',
      );
      expect(
        afterMirror.height,
        250.0,
        reason:
            'height must survive an external canonical mirror, not reset to '
            'the CanvasNode default (132.0).',
      );
      expect(
        afterMirror.isVisible,
        isFalse,
        reason:
            'isVisible must survive an external canonical mirror, not reset '
            'to the CanvasNode default (true).',
      );
    },
  );

  test(
    'applyNodeLayout restores saved layout onto the current graph',
    () async {
      final (:container, :client) = _makeContainer();
      addTearDown(container.dispose);
      container.listen(canvasProvider, (_, _) {});

      container.read(canvasProvider.notifier).addNode(_lifNode());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // (260.0, 198.0) is the exact grid-cell-centered position for a
      // 200x180 node at GridCoord(1, 1) — chosen so _publishGraph's grid-snap
      // (which every graph update goes through) is a no-op here, keeping the
      // position assertion below exact rather than approximate.
      container.read(canvasProvider.notifier).applyNodeLayout(<String, dynamic>{
        'lif_0': {
          'x': 260.0,
          'y': 198.0,
          'width': 200.0,
          'height': 180.0,
          'isVisible': false,
        },
      });

      final node = container
          .read(canvasProvider)
          .graph
          .nodes
          .firstWhere((CanvasNode n) => n.id == 'lif_0');
      expect(node.position, <double>[260.0, 198.0]);
      expect(node.width, 200.0);
      expect(node.height, 180.0);
      expect(node.isVisible, isFalse);
    },
  );
}
