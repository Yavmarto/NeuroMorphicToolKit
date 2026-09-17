import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/services/braille_config_import.dart';

/// The reference braille hyperparameter JSON shape this import maps from.
const Map<String, dynamic> _referenceJson = {
  'nb_hidden': 128,
  'alpha_r': 0.91,
  'beta_r': 0.82,
  'alpha_out': 0.93,
  'beta_out': 0.84,
  'lr': 0.002,
  'slope': 30.0,
  'reg_l1': 2e-5,
  'reg_l2': 3e-5,
};

CanvasNode _archNode({
  required String id,
  required String nirType,
  Map<String, dynamic> parameters = const {},
}) => CanvasNode(
  id: id,
  componentId: nirType,
  nirType: nirType,
  parameters: parameters,
  position: const [0, 0],
);

PipelineDagNode _dagNode({
  required String id,
  required PipelineDagNodeType type,
  Map<String, dynamic> parameters = const {},
}) => PipelineDagNode(id: id, type: type, parameters: parameters);

/// Records every call made through the two update callbacks so tests can
/// assert exactly which node/parameters were targeted.
class _RecordingUpdaters {
  final List<(String nodeId, Map<String, dynamic> parameters)> archCalls = [];
  final List<
    (PipelinePhaseId phase, String nodeId, Map<String, dynamic> parameters)
  >
  dagCalls = [];

  void updateArch(String nodeId, Map<String, dynamic> parameters) {
    archCalls.add((nodeId, parameters));
  }

  void updateDag(
    PipelinePhaseId phase,
    String nodeId,
    Map<String, dynamic> parameters,
  ) {
    dagCalls.add((phase, nodeId, parameters));
  }
}

void main() {
  group('applyBrailleHyperparams', () {
    test('happy path: applies all 9 keys to their single target nodes', () {
      final graph = CanvasGraph(
        nodes: [
          _archNode(id: 'rsyn1', nirType: 'cnl.RSynaptic'),
          _archNode(id: 'syn1', nirType: 'cnl.Synaptic'),
        ],
        edges: const [],
        metadata: const {},
      );
      final phases = PipelinePhases(
        train: PipelineDAG(
          nodes: [
            _dagNode(id: 'adam1', type: PipelineDagNodeType.adamOptimiser),
            _dagNode(id: 'surr1', type: PipelineDagNodeType.surrogateBackward),
            _dagNode(id: 'l1_1', type: PipelineDagNodeType.l1SpikeReg),
            _dagNode(id: 'l2_1', type: PipelineDagNodeType.l2SpikeReg),
          ],
        ),
      );

      final updaters = _RecordingUpdaters();
      final report = applyBrailleHyperparams(
        _referenceJson,
        graph,
        phases,
        updaters.updateArch,
        updaters.updateDag,
      );

      expect(report.applied, hasLength(9));
      expect(report.skipped, isEmpty);

      Map<String, dynamic> archParamsFor(String nodeId) {
        final matches = updaters.archCalls.where((c) => c.$1 == nodeId);
        return {for (final c in matches) ...c.$2};
      }

      Map<String, dynamic> dagParamsFor(String nodeId) {
        final matches = updaters.dagCalls.where((c) => c.$2 == nodeId);
        return {for (final c in matches) ...c.$3};
      }

      expect(archParamsFor('rsyn1')['n_neurons'], 128);
      expect(archParamsFor('rsyn1')['alpha'], 0.91);
      expect(archParamsFor('rsyn1')['beta'], 0.82);
      expect(archParamsFor('syn1')['alpha'], 0.93);
      expect(archParamsFor('syn1')['beta'], 0.84);

      expect(dagParamsFor('adam1')['lr'], 0.002);
      expect(dagParamsFor('surr1')['slope'], 30.0);
      expect(dagParamsFor('l1_1')['weight'], 2e-5);
      expect(dagParamsFor('l2_1')['weight'], 3e-5);

      expect(
        updaters.dagCalls.every((c) => c.$1 == PipelinePhaseId.train),
        isTrue,
      );
    });

    test('missing-node case: alpha_out/beta_out skipped when no cnl.Synaptic '
        'node exists, everything else still applies', () {
      final graph = CanvasGraph(
        nodes: [_archNode(id: 'rsyn1', nirType: 'cnl.RSynaptic')],
        edges: const [],
        metadata: const {},
      );
      final phases = PipelinePhases(
        train: PipelineDAG(
          nodes: [
            _dagNode(id: 'adam1', type: PipelineDagNodeType.adamOptimiser),
            _dagNode(id: 'surr1', type: PipelineDagNodeType.surrogateBackward),
            _dagNode(id: 'l1_1', type: PipelineDagNodeType.l1SpikeReg),
            _dagNode(id: 'l2_1', type: PipelineDagNodeType.l2SpikeReg),
          ],
        ),
      );

      final updaters = _RecordingUpdaters();
      final report = applyBrailleHyperparams(
        _referenceJson,
        graph,
        phases,
        updaters.updateArch,
        updaters.updateDag,
      );

      expect(report.applied, hasLength(7));
      expect(report.skipped, hasLength(2));
      expect(report.skipped.any((s) => s.startsWith('alpha_out:')), isTrue);
      expect(report.skipped.any((s) => s.startsWith('beta_out:')), isTrue);
      expect(report.applied.any((s) => s.contains('nb_hidden')), isTrue);

      expect(updaters.archCalls.any((c) => c.$2.containsKey('alpha')), isTrue);
      // No call ever targets a Synaptic node id because none exists.
      expect(
        updaters.archCalls.where(
          (c) => c.$2.containsKey('alpha') && c.$1 == 'rsyn1',
        ),
        isNotEmpty,
      );
    });

    test('duplicate-node case: two cnl.RSynaptic nodes -> nb_hidden/alpha_r/'
        'beta_r are skipped as ambiguous, not applied to either', () {
      final graph = CanvasGraph(
        nodes: [
          _archNode(id: 'rsyn1', nirType: 'cnl.RSynaptic'),
          _archNode(id: 'rsyn2', nirType: 'cnl.RSynaptic'),
          _archNode(id: 'syn1', nirType: 'cnl.Synaptic'),
        ],
        edges: const [],
        metadata: const {},
      );
      final phases = PipelinePhases(
        train: PipelineDAG(
          nodes: [
            _dagNode(id: 'adam1', type: PipelineDagNodeType.adamOptimiser),
            _dagNode(id: 'surr1', type: PipelineDagNodeType.surrogateBackward),
            _dagNode(id: 'l1_1', type: PipelineDagNodeType.l1SpikeReg),
            _dagNode(id: 'l2_1', type: PipelineDagNodeType.l2SpikeReg),
          ],
        ),
      );

      final updaters = _RecordingUpdaters();
      final report = applyBrailleHyperparams(
        _referenceJson,
        graph,
        phases,
        updaters.updateArch,
        updaters.updateDag,
      );

      expect(report.skipped, hasLength(3));
      expect(report.skipped.every((s) => s.contains('ambiguous')), isTrue);
      expect(report.applied, hasLength(6));

      expect(
        updaters.archCalls.where((c) => c.$1 == 'rsyn1' || c.$1 == 'rsyn2'),
        isEmpty,
      );
    });

    test(
      'empty workspace: no matching nodes at all -> all 9 keys skipped, no exception',
      () {
        final graph = CanvasGraph(
          nodes: const [],
          edges: const [],
          metadata: const {},
        );
        const phases = PipelinePhases();

        final updaters = _RecordingUpdaters();
        final report = applyBrailleHyperparams(
          _referenceJson,
          graph,
          phases,
          updaters.updateArch,
          updaters.updateDag,
        );

        expect(report.applied, isEmpty);
        expect(report.skipped, hasLength(9));
        expect(updaters.archCalls, isEmpty);
        expect(updaters.dagCalls, isEmpty);
      },
    );

    test('keys absent from JSON are skipped rather than throwing', () {
      final graph = CanvasGraph(
        nodes: [
          _archNode(id: 'rsyn1', nirType: 'cnl.RSynaptic'),
          _archNode(id: 'syn1', nirType: 'cnl.Synaptic'),
        ],
        edges: const [],
        metadata: const {},
      );
      const phases = PipelinePhases();

      final updaters = _RecordingUpdaters();
      final report = applyBrailleHyperparams(
        const {'nb_hidden': 64},
        graph,
        phases,
        updaters.updateArch,
        updaters.updateDag,
      );

      expect(report.applied, ['nb_hidden -> cnl.RSynaptic.n_neurons']);
      expect(report.skipped, hasLength(8));
    });
  });
}
