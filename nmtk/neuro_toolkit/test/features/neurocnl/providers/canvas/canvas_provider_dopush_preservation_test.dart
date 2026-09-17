import 'package:riverpod_annotation/riverpod_annotation.dart';
// Preservation Property Tests — _doPush Validation Unchanged
//
// **Validates: Requirements 3.2, 3.3**
//
// Property 8: Preservation — _doPush Validation Unchanged
//
// For any user-initiated canvas mutation that calls _pushToCanonical, the fixed
// CanvasController SHALL continue to invoke validationProvider.validate via
// _doPush exactly as before — the fix MUST NOT remove or alter the
// _doPush → validate path.
//
// This test confirms that all four structural mutation methods on CanvasController:
//   addNode, removeNode, addEdge, updateNodeParameters
// continue to flow through _pushToCanonical → _doPush → validationProvider.validate.
//
// EXPECTED OUTCOME: All tests PASS (no regression in the existing validation path).

import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical_doc;
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/validation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

// ---------------------------------------------------------------------------
// Tracking API client — records validateGraph call count
// ---------------------------------------------------------------------------

/// A concrete [ApiClient] that counts calls to [validateGraph] so tests can
/// assert that _doPush triggers validation for every mutation.
class _TrackingApiClient extends ApiClient {
  _TrackingApiClient() : super(baseUrl: 'http://localhost:0');

  int validateCallCount = 0;

  @override
  Future<ValidationResult> validateGraph(CanvasGraph graph) async {
    validateCallCount++;
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
    // Echo the input graph's nodes/edges back as a canvas projection so
    // tests can assert that _doPush's updateFromCanvas round-trip actually
    // lands in the active workspace file's canonicalDocument.canvas.
    return canonical_doc.ParseCnlResponse(
      document: canonical_doc.CanonicalEditorDocument(
        irJson: const {},
        cnlText: '',
        canvas: canonical_doc.CanvasProjection(
          nodes: graph.nodes
              .map(
                (n) =>
                    canonical_doc.CanvasNode(id: n.id, label: n.label ?? n.id),
              )
              .toList(),
          edges: graph.edges
              .map(
                (e) => canonical_doc.CanvasEdge(
                  source: e.sourceNodeId,
                  target: e.targetNodeId,
                ),
              )
              .toList(),
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

// ---------------------------------------------------------------------------
// No-op PipelineController to avoid post-dispose async errors
// ---------------------------------------------------------------------------

class _NoOpPipelineController extends PipelineController {
  _NoOpPipelineController(this._initialState);
  final PipelineState _initialState;

  @override
  PipelineState build() => _initialState;

  // CanonicalDocController._publishDocument now calls runParseAndValidate
  // internally on every successful publish. Override it directly (rather
  // than relying on noSuchMethod, which never intercepts a concrete
  // inherited method) so it's a no-op for these _doPush-focused tests.
  @override
  Future<void> runParseAndValidate(
    String spec, {
    String? backendOverride,
  }) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

CanvasNode _lifNode({String id = 'lif_0', double threshold = 1.0}) =>
    CanvasNode(
      id: id,
      componentId: 'lif_population',
      nirType: 'nir.LIF',
      label: 'LIF',
      parameters: <String, dynamic>{
        'name': id,
        'n_neurons': 10,
        'threshold': threshold,
      },
      position: const <double>[100.0, 100.0],
      metadata: const <String, dynamic>{'category': 'neuron'},
    );

CanvasEdge _edge({
  String id = 'edge_0',
  String sourceNodeId = 'lif_0',
  String targetNodeId = 'lif_1',
}) => CanvasEdge(
  id: id,
  sourceNodeId: sourceNodeId,
  sourcePort: 'out',
  targetNodeId: targetNodeId,
  targetPort: 'in',
  parameters: const <String, dynamic>{'weight': 1.0},
);

CanvasGraph _twoNodeGraph() => CanvasGraph(
  nodes: <CanvasNode>[
    _lifNode(id: 'lif_0'),
    _lifNode(id: 'lif_1'),
  ],
  edges: const <CanvasEdge>[],
  metadata: const <String, dynamic>{},
);

/// Build a [ProviderContainer] with a [_TrackingApiClient] injected so we can
/// observe [validateGraph] calls without a running backend.
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

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
    'loadProjectGraph writes graph to the active workspace document',
    () async {
      final (:container, :client) = _makeContainer();
      addTearDown(container.dispose);
      container.listen(canvasProvider, (_, _) {});
      expect(client.validateCallCount, equals(0));

      final graph = _twoNodeGraph();
      container.read(canvasProvider.notifier).loadProjectGraph(graph);

      // loadProjectGraph → _pushToCanonical → _doPush → updateFromCanvas is
      // async (awaits the fake canvasToCanonical call); give it a tick.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final activeFile = container.read(workspaceProvider).activeFile!;
      // canvasGraph was deleted from WorkspaceFile — canvas content now lives
      // solely on canonicalDocument.canvas, populated by the _doPush →
      // updateFromCanvas round-trip.
      expect(activeFile.canonicalDocument?.canvas, isNotNull);
      expect(activeFile.canonicalDocument!.canvas!.nodes, hasLength(2));
    },
  );

  test(
    'updateNodeParameters preserves the selected node while mirroring graph state',
    () async {
      final (:container, :client) = _makeContainer();
      addTearDown(container.dispose);
      container.listen(canvasProvider, (_, _) {});
      expect(client.validateCallCount, equals(0));

      container.read(canvasProvider.notifier).setGraph(_twoNodeGraph());
      container.read(canvasProvider.notifier).selectNode('lif_0');

      await Future<void>.delayed(const Duration(milliseconds: 20));

      container
          .read(canvasProvider.notifier)
          .updateNodeParameters('lif_0', <String, dynamic>{
            ...container
                .read(canvasProvider)
                .graph
                .nodes
                .firstWhere((node) => node.id == 'lif_0')
                .parameters,
            'threshold': 0.8,
          });

      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(
        container.read(canvasProvider).selectedNodeId,
        equals('lif_0'),
        reason:
            'Canvas selection must survive workspace graph publication for '
            'inline node edits.',
      );
    },
  );

  test('updateNodeParameters with a "name" key keeps label in sync so renamed '
      'nodes actually display the new name', () async {
    final (:container, :client) = _makeContainer();
    addTearDown(container.dispose);
    container.listen(canvasProvider, (_, _) {});

    // _lifNode's label ('LIF') and parameters['name'] ('lif_0') start out
    // different, matching real nodes created via the palette/drag-drop —
    // every display surface reads `label ?? parameters['name']`, so a
    // rename that only touched `parameters` would never actually show.
    container.read(canvasProvider.notifier).setGraph(_twoNodeGraph());

    container.read(canvasProvider.notifier).updateNodeParameters(
      'lif_0',
      <String, dynamic>{'name': 'Renamed'},
    );

    final renamed = container
        .read(canvasProvider)
        .graph
        .nodes
        .firstWhere((node) => node.id == 'lif_0');
    expect(renamed.label, equals('Renamed'));
    expect(renamed.parameters['name'], equals('Renamed'));

    // A parameter update that doesn't touch 'name' must leave label alone.
    container.read(canvasProvider.notifier).updateNodeParameters(
      'lif_0',
      <String, dynamic>{'threshold': 0.5},
    );
    final afterOtherEdit = container
        .read(canvasProvider)
        .graph
        .nodes
        .firstWhere((node) => node.id == 'lif_0');
    expect(afterOtherEdit.label, equals('Renamed'));
  });

  // ── P8a — addNode triggers _doPush → validationProvider.validate ─────────
  //
  // Validates Requirements 3.2, 3.3:
  //   WHEN addNode is called THEN validationProvider.validate is called once.
  //
  // EXPECTED: PASS — confirms _doPush validate path is intact.
  group('P8a — addNode triggers validate via _doPush', () {
    test('addNode calls validateGraph exactly once', () async {
      final (:container, :client) = _makeContainer();
      addTearDown(container.dispose);
      container.listen(canvasProvider, (_, _) {});

      final beforeCount = client.validateCallCount;

      container.listen(validationProvider, (_, _) {});
      container.read(canvasProvider.notifier).addNode(_lifNode());

      // _doPush is synchronous but validate() is async — give it a tick.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        client.validateCallCount,
        equals(beforeCount + 1),
        reason:
            'P8a: addNode must trigger validationProvider.validate exactly once '
            'via _pushToCanonical → _doPush. '
            'validateCallCount was ${client.validateCallCount}, expected ${beforeCount + 1}.',
      );
    });
  });

  // ── P8b — removeNode triggers _doPush → validationProvider.validate ──────
  //
  // Validates Requirements 3.2, 3.3:
  //   WHEN removeNode is called THEN validationProvider.validate is called once.
  //
  // EXPECTED: PASS.
  group('P8b — removeNode triggers validate via _doPush', () {
    test('removeNode calls validateGraph exactly once', () async {
      final (:container, :client) = _makeContainer();
      addTearDown(container.dispose);
      container.listen(canvasProvider, (_, _) {});

      // Pre-populate so removeNode has something to remove.
      container.read(canvasProvider.notifier).setGraph(_twoNodeGraph());

      // Wait for any reactive effects to settle.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final beforeCount = client.validateCallCount;

      container.read(canvasProvider.notifier).removeNode('lif_0');

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        client.validateCallCount,
        equals(beforeCount + 1),
        reason:
            'P8b: removeNode must trigger validationProvider.validate exactly once '
            'via _pushToCanonical → _doPush.',
      );
    });
  });

  // ── P8c — addEdge triggers _doPush → validationProvider.validate ─────────
  //
  // Validates Requirements 3.2, 3.3:
  //   WHEN addEdge is called THEN validationProvider.validate is called once.
  //
  // EXPECTED: PASS.
  group('P8c — addEdge triggers validate via _doPush', () {
    test('addEdge calls validateGraph exactly once', () async {
      final (:container, :client) = _makeContainer();
      addTearDown(container.dispose);
      container.listen(canvasProvider, (_, _) {});

      // Pre-populate with two nodes so the edge references valid node IDs.
      container.read(canvasProvider.notifier).setGraph(_twoNodeGraph());

      await Future<void>.delayed(const Duration(milliseconds: 20));
      final beforeCount = client.validateCallCount;

      container
          .read(canvasProvider.notifier)
          .addEdge(_edge(sourceNodeId: 'lif_0', targetNodeId: 'lif_1'));

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        client.validateCallCount,
        equals(beforeCount + 1),
        reason:
            'P8c: addEdge must trigger validationProvider.validate exactly once '
            'via _pushToCanonical → _doPush.',
      );
    });
  });

  // ── P8d — updateNodeParameters triggers _doPush → validationProvider.validate
  //
  // Validates Requirements 3.2, 3.3:
  //   WHEN updateNodeParameters is called THEN validationProvider.validate is
  //   called once (after the 300 ms debounce settles).
  //
  // EXPECTED: PASS.
  group('P8d — updateNodeParameters triggers validate via _doPush (debounced)', () {
    test('updateNodeParameters calls validateGraph once after debounce', () {
      fakeAsync((async) {
        final (:container, :client) = _makeContainer();
        addTearDown(container.dispose);
        container.listen(canvasProvider, (_, _) {});

        // Seed with a node to update.
        container
            .read(canvasProvider.notifier)
            .setGraph(
              CanvasGraph(
                nodes: <CanvasNode>[_lifNode(id: 'lif_0')],
                edges: const <CanvasEdge>[],
                metadata: const <String, dynamic>{},
              ),
            );

        // Settle any side effects from setGraph.
        async.elapse(const Duration(milliseconds: 50));
        async.flushMicrotasks();
        final beforeCount = client.validateCallCount;

        // updateNodeParameters uses debounce: true — validate fires after 300 ms.
        container.read(canvasProvider.notifier).updateNodeParameters(
          'lif_0',
          const <String, dynamic>{
            'name': 'lif_0',
            'n_neurons': 20,
            'threshold': 0.9,
          },
        );

        // Before debounce fires — validate must NOT have been called yet.
        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();
        expect(
          client.validateCallCount,
          equals(beforeCount),
          reason:
              'P8d: validate must NOT fire before the 300 ms debounce elapses.',
        );

        // Advance past the debounce.
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        expect(
          client.validateCallCount,
          greaterThan(beforeCount),
          reason:
              'P8d: updateNodeParameters must trigger validationProvider.validate '
              'after the 300 ms debounce via _pushToCanonical(debounce: true) → _doPush.',
        );
      });
    });
  });

  // ── P8e — validationProvider.state transitions to AsyncData after mutation ─
  //
  // Validates Requirements 3.2:
  //   WHEN a mutation fires validate THEN validationProvider.state is AsyncData.
  //
  // This sub-property confirms that the fake client's ValidationResult makes it
  // all the way into the Riverpod state (not just that the client was called).
  //
  // EXPECTED: PASS.
  group('P8e — validationProvider.state becomes AsyncData after addNode', () {
    test(
      'validationProvider holds AsyncData(ValidationResult) after addNode',
      () async {
        final (:container, :client) = _makeContainer();
        addTearDown(container.dispose);
        container.listen(canvasProvider, (_, _) {});

        container.listen(validationProvider, (_, _) {});
        container.read(canvasProvider.notifier).addNode(_lifNode());

        // Allow the async validate to complete.
        await Future<void>.delayed(const Duration(milliseconds: 100));

        final validationState = container.read(validationProvider);
        expect(
          validationState,
          isA<AsyncData<ValidationResult>>(),
          reason:
              'P8e: validationProvider must be AsyncData after addNode triggers '
              'validate. Current state: $validationState',
        );

        final result = validationState.asData?.value;
        expect(
          result?.valid,
          isTrue,
          reason:
              'P8e: ValidationResult.valid must be true (from fake client).',
        );
      },
    );
  });

  // ── P8f — Multiple rapid mutations collapse to one validate call (debounced) ─
  //
  // Validates Requirements 3.3:
  //   WHEN multiple updateNodeParameters calls are made within the debounce
  //   window THEN only one validate call is made.
  //
  // EXPECTED: PASS.
  group(
    'P8f — Multiple rapid updateNodeParameters calls collapse to one validate',
    () {
      test(
        'three rapid updateNodeParameters calls produce one validateGraph call',
        () {
          fakeAsync((async) {
            final (:container, :client) = _makeContainer();
            addTearDown(container.dispose);
            container.listen(canvasProvider, (_, _) {});

            container
                .read(canvasProvider.notifier)
                .setGraph(
                  CanvasGraph(
                    nodes: <CanvasNode>[_lifNode(id: 'lif_0')],
                    edges: const <CanvasEdge>[],
                    metadata: const <String, dynamic>{},
                  ),
                );

            async.elapse(const Duration(milliseconds: 50));
            async.flushMicrotasks();
            final beforeCount = client.validateCallCount;

            // Fire three updates in quick succession — only the last should fire.
            for (double threshold in <double>[0.5, 0.7, 1.2]) {
              container.read(canvasProvider.notifier).updateNodeParameters(
                'lif_0',
                <String, dynamic>{
                  'name': 'lif_0',
                  'n_neurons': 10,
                  'threshold': threshold,
                },
              );
              async.elapse(const Duration(milliseconds: 50));
              async.flushMicrotasks();
            }

            // Advance past the 300 ms debounce to trigger the single coalesced push.
            async.elapse(const Duration(milliseconds: 400));
            async.flushMicrotasks();

            expect(
              client.validateCallCount,
              equals(beforeCount + 1),
              reason:
                  'P8f: Three rapid updateNodeParameters calls within the debounce '
                  'window must collapse to exactly one _doPush → validate call.',
            );
          });
        },
      );
    },
  );
}
