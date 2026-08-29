import 'package:riverpod_annotation/riverpod_annotation.dart';
// Validates that debounced canvas parameter pushes do not re-mirror the
// canonical projection back into canvasProvider (echo loop).

import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

class _TrackingApiClient extends ApiClient {
  _TrackingApiClient() : super(baseUrl: 'http://localhost:0');

  int canvasToCanonicalCallCount = 0;

  @override
  Future<canonical_doc.ParseCnlResponse> canvasToCanonical(
    CanvasGraph graph,
  ) async {
    canvasToCanonicalCallCount++;
    return canonical_doc.ParseCnlResponse(
      document: canonical_doc.CanonicalEditorDocument(
        cnlText: 'threshold=${graph.nodes.first.parameters['threshold']}',
        canvas: canonical_doc.CanvasProjection(
          nodes: [
            canonical_doc.CanvasNode(
              id: graph.nodes.first.id,
              label: graph.nodes.first.label ?? 'lif',
              size: graph.nodes.first.parameters['n_neurons'] as int? ?? 1,
              threshold: graph.nodes.first.parameters['threshold'] as double?,
            ),
          ],
          edges: const [],
        ),
        irJson: const {},
      ),
      diagnostics: const [],
    );
  }

  @override
  Future<ValidationResult> validateGraph(CanvasGraph graph) async {
    return ValidationResult(valid: true, errors: []);
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
  Future<canonical_doc.ParseCnlResponse> parseCnlCanonical(String cnl) async {
    return const canonical_doc.ParseCnlResponse(
      document: canonical_doc.CanonicalEditorDocument(irJson: {}, cnlText: ''),
      diagnostics: [],
    );
  }
}

CanvasNode _lifNode({double threshold = 1.0}) => CanvasNode(
  id: 'lif_0',
  componentId: 'lif_population',
  nirType: 'nir.LIF',
  label: 'LIF',
  parameters: <String, dynamic>{
    'name': 'lif_0',
    'n_neurons': 10,
    'threshold': threshold,
  },
  position: const <double>[100, 100],
  metadata: const <String, dynamic>{'category': 'neuron'},
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
  });

  group('canvas echo loop', () {
    test('canvasPush does not re-mirror graph after parameter debounce', () {
      fakeAsync((async) {
        final client = _TrackingApiClient();
        final container = ProviderContainer(
          overrides: [canvas_sync.apiClientProvider.overrideWithValue(client)],
        );
        addTearDown(container.dispose);
        // Keep the autoDispose canvasProvider alive across the debounce
        // timer — without an active listener it would be disposed on the
        // next microtask flush, cancelling the pending Timer.
        container.listen(canvasProvider, (_, _) {});

        container
            .read(canvasProvider.notifier)
            .setGraph(
              CanvasGraph(
                nodes: <CanvasNode>[_lifNode()],
                edges: const <CanvasEdge>[],
                metadata: const <String, dynamic>{},
              ),
            );
        async.elapse(const Duration(milliseconds: 50));
        async.flushMicrotasks();

        container.read(canvasProvider.notifier).updateNodeParameters(
          'lif_0',
          <String, dynamic>{
            'name': 'lif_0',
            'n_neurons': 10,
            'threshold': 0.42,
          },
        );

        expect(
          container
              .read(canvasProvider)
              .graph
              .nodes
              .first
              .parameters['threshold'],
          closeTo(0.42, 0.0001),
        );

        async.elapse(const Duration(milliseconds: 350));
        async.flushMicrotasks();

        expect(client.canvasToCanonicalCallCount, greaterThan(0));

        expect(
          container
              .read(canvasProvider)
              .graph
              .nodes
              .first
              .parameters['threshold'],
          closeTo(0.42, 0.0001),
          reason:
              'Echo mirror must not overwrite parameters after canvas push.',
        );
      });
    });
  });
}
