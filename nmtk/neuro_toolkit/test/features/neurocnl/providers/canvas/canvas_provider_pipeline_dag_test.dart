import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    hide CanvasEdge, CanvasNode;
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_config.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://localhost:0');

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

  // Graph mutations fire a canonical-doc push and a validation pass. Left
  // unstubbed they attempt real HTTP, and the continuation can outlive the
  // test — which fails it with "used Ref after dispose" even though every
  // assertion passed.
  @override
  Future<ParseCnlResponse> canvasToCanonical(CanvasGraph graph) async =>
      const ParseCnlResponse(document: CanonicalEditorDocument(irJson: {}));

  @override
  Future<ValidationResult> validateGraph(CanvasGraph graph) async =>
      ValidationResult(valid: true, errors: const []);
}

/// Lets the fire-and-forget canonical-doc push finish inside the test body,
/// before the tear-down disposes the container out from under it.
Future<void> _settlePushes() => Future<void>.delayed(Duration.zero);

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

  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
  });

  group('canvasProvider — fresh-session reset', () {
    test('clears pipeline state and suppresses automatic starter DAGs', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(canvasProvider.notifier);

      notifier.initDefaultPhases(
        frameworks: const ['snntorch_sim'],
        dataset: 'nmnist',
      );
      notifier.updatePipeline(const PipelineConfig(epochs: 99));
      notifier.setActiveTab(CanvasTab.pipelineEval);
      notifier.restoreSelection(
        selectedNodeIds: const {'train_dataloader'},
        selectedEdgeId: 'te1',
      );

      notifier.resetPipelineForFreshSession();

      var state = container.read(canvasProvider);
      expect(state.pipeline, const PipelineConfig());
      expect(state.pipelinePhases.isEmpty, isTrue);
      expect(state.activeTab, CanvasTab.architecture);
      expect(state.selectedNodeIds, isEmpty);
      expect(state.selectedEdgeId, isNull);
      expect(state.pendingViewportFocusNodeId, isNull);

      notifier.initDefaultPhases(
        frameworks: const ['snntorch_sim'],
        dataset: 'nmnist',
      );

      state = container.read(canvasProvider);
      expect(
        state.pipelinePhases.isEmpty,
        isTrue,
        reason: 'Start Fresh must keep Train/Eval blank when opened.',
      );
    });

    test(
      'explicit workspace restore re-enables starter DAG initialization',
      () {
        final container = _makeContainer();
        addTearDown(container.dispose);
        final notifier = container.read(canvasProvider.notifier);

        notifier.resetPipelineForFreshSession();
        notifier.restorePipelineState(
          pipeline: const PipelineConfig(),
          pipelinePhases: const PipelinePhases(),
        );
        notifier.initDefaultPhases(
          frameworks: const ['snntorch_sim'],
          dataset: 'nmnist',
        );

        expect(container.read(canvasProvider).pipelinePhases.isEmpty, isFalse);
      },
    );
  });

  group('canvasProvider — updatePipelineDagNodeParams merge behavior', () {
    test('updatePipelineDagNodeParams merges parameters into live state, '
        'not replacing them', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      // Initialize default pipeline phases first
      container
          .read(canvasProvider.notifier)
          .initDefaultPhases(frameworks: ['snntorch_sim'], dataset: 'nmnist');

      // Get the data loader node (should be in the default phases)
      var state = container.read(canvasProvider);
      final dataLoaderNode = state.pipelinePhases.train.nodes.firstWhere(
        (n) => n.type == PipelineDagNodeType.dataLoader,
      );
      final nodeId = dataLoaderNode.id;

      // Manually update the first node to have a known state
      container.read(canvasProvider.notifier).updatePipelineDagNodeParams(
        PipelinePhaseId.train,
        nodeId,
        {'format': 'pt', 'batch_size': 32, 'shuffle': true},
      );

      state = container.read(canvasProvider);
      var node = state.pipelinePhases.train.nodes.firstWhere(
        (n) => n.id == nodeId,
      );
      expect(node.parameters['format'], equals('pt'));
      expect(node.parameters['batch_size'], equals(32));
      expect(node.parameters['shuffle'], isTrue);

      // First update: change format only
      container.read(canvasProvider.notifier).updatePipelineDagNodeParams(
        PipelinePhaseId.train,
        nodeId,
        {'format': 'npy'},
      );

      state = container.read(canvasProvider);
      node = state.pipelinePhases.train.nodes.firstWhere((n) => n.id == nodeId);
      expect(node.parameters['format'], equals('npy'));
      expect(
        node.parameters['batch_size'],
        equals(32),
        reason: 'Batch size should be preserved from initial setup.',
      );
      expect(
        node.parameters['shuffle'],
        isTrue,
        reason: 'Shuffle should be preserved from initial setup.',
      );

      // Second update: change batch_size only (after format change is live)
      container.read(canvasProvider.notifier).updatePipelineDagNodeParams(
        PipelinePhaseId.train,
        nodeId,
        {'batch_size': 64},
      );

      state = container.read(canvasProvider);
      node = state.pipelinePhases.train.nodes.firstWhere((n) => n.id == nodeId);
      expect(
        node.parameters['format'],
        equals('npy'),
        reason: 'Format should persist from first update.',
      );
      expect(node.parameters['batch_size'], equals(64));
      expect(
        node.parameters['shuffle'],
        isTrue,
        reason: 'Shuffle should still be true (was never in any update map).',
      );
    });

    test('two sequential updatePipelineDagNodeParams calls with disjoint '
        'parameter sets both persist', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      // Initialize default pipeline phases
      container
          .read(canvasProvider.notifier)
          .initDefaultPhases(frameworks: ['snntorch_sim'], dataset: 'nmnist');

      // Find the optimizer node
      var state = container.read(canvasProvider);
      final optNode = state.pipelinePhases.train.nodes.firstWhere(
        (n) => n.type == PipelineDagNodeType.adamOptimiser,
      );
      final nodeId = optNode.id;

      // Update 1: change learning rate
      container.read(canvasProvider.notifier).updatePipelineDagNodeParams(
        PipelinePhaseId.train,
        nodeId,
        {'lr': 0.005},
      );

      state = container.read(canvasProvider);
      var node = state.pipelinePhases.train.nodes.firstWhere(
        (n) => n.id == nodeId,
      );
      expect(node.parameters['lr'], closeTo(0.005, 1e-9));
      // weight_decay should still be there from default
      expect(node.parameters.containsKey('weight_decay'), isTrue);

      // Update 2: change weight_decay (separate from lr update)
      container.read(canvasProvider.notifier).updatePipelineDagNodeParams(
        PipelinePhaseId.train,
        nodeId,
        {'weight_decay': 0.01},
      );

      state = container.read(canvasProvider);
      node = state.pipelinePhases.train.nodes.firstWhere((n) => n.id == nodeId);
      expect(
        node.parameters['lr'],
        closeTo(0.005, 1e-9),
        reason: 'Learning rate from first update should persist.',
      );
      expect(
        node.parameters['weight_decay'],
        closeTo(0.01, 1e-9),
        reason: 'Weight decay should be updated in second call.',
      );
    });
  });

  group('canvasProvider — updateNodeParameters merge behavior', () {
    test('updateNodeParameters merges parameters into live state, '
        'not replacing them', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      // Create initial graph with a single node
      final initialNode = CanvasNode(
        id: 'nir_node_1',
        componentId: 'lif_pop',
        nirType: 'nir.LIF',
        label: 'Test LIF',
        parameters: const {'n_neurons': 10, 'threshold': 1.0, 'tau': 0.02},
        position: const [100.0, 100.0],
        metadata: const {},
      );

      final graph = CanvasGraph(
        nodes: [initialNode],
        edges: const [],
        metadata: const {},
      );

      container.read(canvasProvider.notifier).setGraph(graph);

      // First update: change threshold only
      container.read(canvasProvider.notifier).updateNodeParameters(
        'nir_node_1',
        {'threshold': 0.8},
      );

      var state = container.read(canvasProvider);
      var node = state.graph.nodes.firstWhere((n) => n.id == 'nir_node_1');
      expect(node.parameters['threshold'], closeTo(0.8, 1e-9));
      expect(
        node.parameters['n_neurons'],
        equals(10),
        reason: 'n_neurons should be preserved from initial state.',
      );
      expect(
        node.parameters['tau'],
        closeTo(0.02, 1e-9),
        reason: 'tau should be preserved from initial state.',
      );

      // Second update: change n_neurons only (after threshold change is live)
      container.read(canvasProvider.notifier).updateNodeParameters(
        'nir_node_1',
        {'n_neurons': 20},
      );

      state = container.read(canvasProvider);
      node = state.graph.nodes.firstWhere((n) => n.id == 'nir_node_1');
      expect(
        node.parameters['threshold'],
        closeTo(0.8, 1e-9),
        reason: 'Threshold should persist from first update.',
      );
      expect(node.parameters['n_neurons'], equals(20));
      expect(
        node.parameters['tau'],
        closeTo(0.02, 1e-9),
        reason: 'tau should still be 0.02 (was never in any update map).',
      );
    });

    test('two sequential updateNodeParameters calls with disjoint parameter '
        'sets both persist', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final initialNode = CanvasNode(
        id: 'lif_2',
        componentId: 'lif_pop',
        nirType: 'nir.LIF',
        label: 'LIF',
        parameters: const {'n_neurons': 5, 'threshold': 1.0},
        position: const [50.0, 50.0],
        metadata: const {},
      );

      final graph = CanvasGraph(
        nodes: [initialNode],
        edges: const [],
        metadata: const {},
      );

      container.read(canvasProvider.notifier).setGraph(graph);

      // Update 1: change n_neurons
      container.read(canvasProvider.notifier).updateNodeParameters('lif_2', {
        'n_neurons': 15,
      });

      var state = container.read(canvasProvider);
      var node = state.graph.nodes.firstWhere((n) => n.id == 'lif_2');
      expect(node.parameters['n_neurons'], equals(15));
      expect(node.parameters['threshold'], closeTo(1.0, 1e-9));

      // Update 2: change threshold (disjoint from Update 1)
      container.read(canvasProvider.notifier).updateNodeParameters('lif_2', {
        'threshold': 0.5,
      });

      state = container.read(canvasProvider);
      node = state.graph.nodes.firstWhere((n) => n.id == 'lif_2');
      expect(
        node.parameters['n_neurons'],
        equals(15),
        reason: 'n_neurons from first update should persist.',
      );
      expect(
        node.parameters['threshold'],
        closeTo(0.5, 1e-9),
        reason: 'Threshold should be updated in second call.',
      );
    });
  });

  group('canvasProvider — infer phase updates', () {
    test(
      'addPipelineDagNode(infer, ...) lands the node in pipelinePhases.infer',
      () {
        final container = _makeContainer();
        addTearDown(container.dispose);

        const node = PipelineDagNode(
          id: 'infer_node_1',
          type: PipelineDagNodeType.dataLoader,
          parameters: {},
        );

        container
            .read(canvasProvider.notifier)
            .addPipelineDagNode(PipelinePhaseId.infer, node);

        final state = container.read(canvasProvider);
        expect(
          state.pipelinePhases.infer.nodes.any((n) => n.id == 'infer_node_1'),
          isTrue,
          reason:
              '_phasesWithUpdated must merge the infer phase, not silently '
              'discard it.',
        );
      },
    );
  });

  group('PipelineDagNode — hashCode consistency', () {
    test(
      'nodes with same data but different parameters have different hashes',
      () {
        const node1 = PipelineDagNode(
          id: 'n1',
          type: PipelineDagNodeType.dataLoader,
          parameters: {'format': 'pt', 'batch_size': 32},
        );

        const node2 = PipelineDagNode(
          id: 'n1',
          type: PipelineDagNodeType.dataLoader,
          parameters: {'format': 'npy', 'batch_size': 32},
        );

        expect(
          node1.hashCode,
          isNot(node2.hashCode),
          reason:
              'Nodes with different parameters should have different hashes.',
        );
      },
    );

    test('nodes with identical data have same hash', () {
      const node1 = PipelineDagNode(
        id: 'n1',
        type: PipelineDagNodeType.adamOptimiser,
        x: 10,
        y: 20,
        parameters: {'lr': 0.001, 'weight_decay': 0.0},
      );

      const node2 = PipelineDagNode(
        id: 'n1',
        type: PipelineDagNodeType.adamOptimiser,
        x: 10,
        y: 20,
        parameters: {'lr': 0.001, 'weight_decay': 0.0},
      );

      expect(
        node1.hashCode,
        equals(node2.hashCode),
        reason: 'Identical nodes should have identical hashes.',
      );
    });

    test('hashCode and == are consistent', () {
      const node1 = PipelineDagNode(
        id: 'n1',
        type: PipelineDagNodeType.dataLoader,
        parameters: {'format': 'pt'},
      );

      const node2 = PipelineDagNode(
        id: 'n1',
        type: PipelineDagNodeType.dataLoader,
        parameters: {'format': 'pt'},
      );

      expect(node1, equals(node2));
      expect(
        node1.hashCode,
        equals(node2.hashCode),
        reason: 'If a == b then a.hashCode must equal b.hashCode (contract).',
      );
    });
  });

  group('addNodeWithEdge — port-anchored add is one undo step', () {
    CanvasNode node(String id) => CanvasNode(
      id: id,
      componentId: 'nir.LIF',
      nirType: 'nir.LIF',
      label: id,
      position: const <double>[0, 0],
      width: 200,
      height: 160,
      parameters: const <String, dynamic>{},
    );

    test('adds the node and its edge together', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(canvasProvider.notifier);

      notifier.addNode(node('source'));
      notifier.addNodeWithEdge(
        node('added'),
        (CanvasNode placed) => CanvasEdge(
          id: 'edge_${placed.id}',
          sourceNodeId: 'source',
          sourcePort: 'out',
          targetNodeId: placed.id,
          targetPort: 'in',
          parameters: const <String, dynamic>{},
        ),
      );

      final graph = container.read(canvasProvider).graph;
      expect(graph.nodes.map((n) => n.id), containsAll(['source', 'added']));
      expect(graph.edges, hasLength(1));
      expect(graph.edges.single.sourceNodeId, 'source');
      expect(graph.edges.single.targetNodeId, 'added');

      await _settlePushes();
    });

    test('one undo removes both, not just the edge', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(canvasProvider.notifier);

      notifier.addNode(node('source'));
      notifier.addNodeWithEdge(
        node('added'),
        (CanvasNode placed) => CanvasEdge(
          id: 'edge_${placed.id}',
          sourceNodeId: 'source',
          sourcePort: 'out',
          targetNodeId: placed.id,
          targetPort: 'in',
          parameters: const <String, dynamic>{},
        ),
      );

      notifier.undo();

      final graph = container.read(canvasProvider).graph;
      expect(graph.edges, isEmpty);
      expect(graph.nodes.map((n) => n.id), <String>['source']);

      await _settlePushes();
    });

    test('the edge builder sees the grid-snapped position', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(canvasProvider.notifier);

      notifier.addNode(node('source'));

      List<double>? seenPosition;
      notifier.addNodeWithEdge(node('added'), (CanvasNode placed) {
        seenPosition = placed.position;
        return CanvasEdge(
          id: 'edge_${placed.id}',
          sourceNodeId: 'source',
          sourcePort: 'out',
          targetNodeId: placed.id,
          targetPort: 'in',
          parameters: const <String, dynamic>{},
        );
      });

      final placed = container
          .read(canvasProvider)
          .graph
          .nodes
          .firstWhere((n) => n.id == 'added');
      expect(seenPosition, isNotNull);
      expect(seenPosition, placed.position);

      await _settlePushes();
    });
  });
}
