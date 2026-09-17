// Panning/zooming the canvas must not look like an edit to the document.
//
// Bug: updateViewport stored zoom/pan in `graph.metadata`, so every pan frame
// minted a new CanvasGraph. CanvasGraph compares by identity, so that
// invalidated every `select((s) => s.graph)` in the app at once — the whole
// NetworkCanvas build plus every node widget rebuilt per frame (the lag), and
// studio_screen's workspace autosave listener fired, fsyncing the workspace
// cache and the .nmtk file 300ms after every pan (the spurious saves).
//
// Fix: pan/zoom lives on CanvasState.viewport. `graph` keeps its identity.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
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
  metadata: const <String, dynamic>{'category': 'neuron'},
);

ProviderContainer _makeContainer() {
  final container = ProviderContainer(
    overrides: [
      canvas_sync.apiClientProvider.overrideWithValue(_FakeApiClient()),
    ],
  );
  container
      .read(canvasProvider.notifier)
      .setGraph(
        CanvasGraph(
          nodes: <CanvasNode>[_node('a', 0, 0), _node('b', 200, 0)],
          edges: const <CanvasEdge>[],
          metadata: const <String, dynamic>{},
        ),
      );
  return container;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
  });

  group('viewport is view state, not document state', () {
    test('updateViewport leaves graph identity intact', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final before = container.read(canvasProvider).graph;
      container
          .read(canvasProvider.notifier)
          .updateViewport(zoom: 1.75, pan: <double>[-320, 96]);
      final after = container.read(canvasProvider);

      // The camera moved...
      expect(after.viewport.zoom, 1.75);
      expect(after.viewport.pan, <double>[-320, 96]);
      // ...but the document did not. This identity check is the whole point:
      // it is what every `select((s) => s.graph)` downstream relies on, and
      // what stops the workspace autosave from firing on a pan.
      expect(identical(before, after.graph), isTrue);
    });

    test('graph metadata carries no zoom/pan keys', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      container
          .read(canvasProvider.notifier)
          .updateViewport(zoom: 0.5, pan: <double>[10, 20]);

      final metadata = container.read(canvasProvider).graph.metadata;
      expect(metadata.containsKey('zoom'), isFalse);
      expect(metadata.containsKey('pan'), isFalse);
    });

    test('workspace restore focus clears stale interaction state once', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(canvasProvider.notifier);

      notifier.selectNode('a');
      notifier.updateViewport(zoom: 1.5, pan: <double>[40, 24]);
      notifier.requestWorkspaceRestoreFocus();

      final CanvasState afterFirst = container.read(canvasProvider);
      expect(afterFirst.workspaceRestoreFocusRevision, 1);
      expect(afterFirst.selectedNodeIds, isEmpty);
      expect(afterFirst.viewport, CanvasViewport.defaults);

      notifier.requestWorkspaceRestoreFocus();
      expect(container.read(canvasProvider).workspaceRestoreFocusRevision, 2);
    });

    test(
      'workspace restore keeps model and pipeline nodes in signed scene space',
      () {
        final container = _makeContainer();
        addTearDown(container.dispose);
        final notifier = container.read(canvasProvider.notifier);

        notifier.requestWorkspaceRestoreFocus();
        notifier.selectNode('a');
        notifier.updateNodePosition('a', 0, -64);
        expect(container.read(canvasProvider).selectedNodeIds, {'a'});
        expect(
          container.read(canvasProvider).graph.nodes.first.position[1],
          -64,
        );

        for (final phase in <PipelinePhaseId>[
          PipelinePhaseId.train,
          PipelinePhaseId.eval,
        ]) {
          final id = '${phase.name}_upper';
          notifier.addPipelineDagNode(
            phase,
            PipelineDagNode(
              id: id,
              type: PipelineDagNodeType.dataLoader,
              x: 40,
              y: 100,
            ),
          );
          notifier.requestWorkspaceRestoreFocus();
          notifier.selectNode(id);
          notifier.movePipelineDagNode(phase, id, 0, -80);
          final node = container
              .read(canvasProvider)
              .pipelinePhases
              .dagFor(phase)
              .nodes
              .singleWhere((node) => node.id == id);
          expect(container.read(canvasProvider).selectedNodeIds, {id});
          expect(node.y, lessThan(0));
        }
      },
    );

    test(
      'workspace layout restore preserves a negative model-node position',
      () {
        final container = _makeContainer();
        addTearDown(container.dispose);

        container.read(canvasProvider.notifier).applyNodeLayout({
          'a': {
            'x': 40,
            'y': -200,
            'width': 200,
            'height': 160,
            'isVisible': true,
          },
        });

        expect(
          container.read(canvasProvider).graph.nodes.first.position[1],
          -200,
        );
      },
    );

    test('a real edit does change graph identity', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final before = container.read(canvasProvider).graph;
      container.read(canvasProvider.notifier).updateNodePosition('a', 64, 64);

      // Guards the other direction: the autosave listener selects on `graph`,
      // so a genuine mutation must still invalidate it.
      expect(identical(before, container.read(canvasProvider).graph), isFalse);
    });

    // Taking the viewport off the graph nearly dropped this on the floor: a
    // saved *project* does round-trip zoom/pan through graph.metadata (the
    // workspace autosave does not), so the load and save boundaries have to
    // hydrate and re-fold it explicitly.
    test('loadProjectGraph hydrates the camera out of graph metadata', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      container
          .read(canvasProvider.notifier)
          .loadProjectGraph(
            CanvasGraph(
              nodes: <CanvasNode>[_node('a', 0, 0)],
              edges: const <CanvasEdge>[],
              metadata: const <String, dynamic>{
                'zoom': 1.25,
                'pan': <double>[8, 16],
              },
            ),
          );

      final viewport = container.read(canvasProvider).viewport;
      expect(viewport.zoom, 1.25);
      expect(viewport.pan, <double>[8, 16]);
      expect(container.read(canvasProvider).workspaceRestoreFocusRevision, 0);
    });

    test('graphForPersistence folds the live camera back into metadata', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      container
          .read(canvasProvider.notifier)
          .updateViewport(zoom: 2.0, pan: <double>[-40, 12]);

      final persisted = container.read(canvasProvider).graphForPersistence;
      expect(persisted.metadata['zoom'], 2.0);
      expect(persisted.metadata['pan'], <double>[-40, 12]);
      // Round-trips: what a project stores is what reloading it restores.
      final restored = CanvasViewport.fromMetadata(persisted.metadata);
      expect(restored, const CanvasViewport(zoom: 2.0, pan: <double>[-40, 12]));
    });

    test('a no-op pan within tolerance emits nothing', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(canvasProvider.notifier);
      notifier.updateViewport(zoom: 1.5, pan: <double>[8, 8]);
      final settled = container.read(canvasProvider);

      notifier.updateViewport(zoom: 1.5, pan: <double>[8, 8]);
      expect(identical(settled, container.read(canvasProvider)), isTrue);
    });

    // Exercises the exact selector studio_screen's workspace autosave listener
    // subscribes to. Nothing else covers that wiring, and getting it wrong in
    // either direction is silent: too eager and a pan fsyncs the workspace
    // cache and the .nmtk file; too lazy and real edits stop being saved.
    test('the autosave selector fires on edits and not on pans', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      var notifications = 0;
      final sub = container.listen<CanvasGraph>(
        canvasProvider.select((CanvasState s) => s.graph),
        (_, _) => notifications++,
      );
      addTearDown(sub.close);

      final notifier = container.read(canvasProvider.notifier);

      notifier.updateViewport(zoom: 1.4, pan: <double>[-100, 40]);
      notifier.updateViewport(zoom: 1.9, pan: <double>[-260, 90]);
      expect(
        notifications,
        0,
        reason: 'panning/zooming must not schedule a workspace write',
      );

      notifier.updateNodePosition('a', 96, 96);
      expect(
        notifications,
        greaterThan(0),
        reason: 'a real edit must still schedule a workspace write',
      );
    });

    // Regression: the selector above was briefly narrowed to `s.graph` alone,
    // which silently stopped persisting the Train and Eval canvases entirely —
    // a pipeline edit never touches `graph`, so the "eval grid" came back empty
    // after a restart. All three canvases must reach the autosave.
    test('the autosave selector also fires for Train and Eval edits', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(canvasProvider.notifier);
      notifier.initDefaultPhases(frameworks: const ['snntorch'], dataset: null);

      var notifications = 0;
      final sub = container.listen(
        canvasProvider.select(
          (CanvasState s) => (s.graph, s.pipelinePhases, s.pipeline),
        ),
        (_, _) => notifications++,
      );
      addTearDown(sub.close);

      // train + eval only: those are the two mounted pipeline canvases (steps 2
      // and 3). PipelinePhaseId.infer has no canvas and no seeded defaults.
      for (final phase in const [PipelinePhaseId.train, PipelinePhaseId.eval]) {
        final before = notifications;
        final dag = container.read(canvasProvider).pipelinePhases.dagFor(phase);
        expect(
          dag.nodes,
          isNotEmpty,
          reason: 'default phases should have seeded $phase',
        );
        notifier.movePipelineDagNode(phase, dag.nodes.first.id, 321, 654);
        expect(
          notifications,
          greaterThan(before),
          reason: 'a $phase canvas edit must schedule a workspace write',
        );
      }
    });
  });
}
