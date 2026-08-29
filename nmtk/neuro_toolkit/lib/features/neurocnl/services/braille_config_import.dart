import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';

/// Result of [applyBrailleHyperparams]: which of the 9 reference
/// hyperparameter keys were applied to a live node, and which were skipped
/// (with a human-readable reason) because the target node type was missing
/// or ambiguous in the current architecture graph / Training-DAG.
class ConfigImportReport {
  const ConfigImportReport({this.applied = const [], this.skipped = const []});

  final List<String> applied;
  final List<String> skipped;

  bool get isEmpty => applied.isEmpty && skipped.isEmpty;
}

/// Applies a single parameter update to an architecture-canvas node.
typedef ArchNodeParamUpdater =
    void Function(String nodeId, Map<String, dynamic> parameters);

/// Applies a single parameter update to a Training-DAG node in [phase].
typedef DagNodeParamUpdater =
    void Function(
      PipelinePhaseId phase,
      String nodeId,
      Map<String, dynamic> parameters,
    );

/// Maps the reference braille hyperparameter JSON
/// (`nb_hidden, alpha_r, beta_r, alpha_out, beta_out, lr, slope, reg_l1,
/// reg_l2`) onto the live architecture graph and Training-DAG node
/// parameters.
///
/// Matches the *first* node of the required type per key. If a required
/// node type has zero matches or more than one match in the current
/// [graph]/[pipelinePhases], the key is recorded as skipped rather than
/// guessed at.
///
/// Pure/testable: [graph] and [pipelinePhases] are read-only snapshots and
/// mutation only happens through [updateArchNode]/[updateDagNode] — no
/// `ref.read`/widget dependency here.
ConfigImportReport applyBrailleHyperparams(
  Map<String, dynamic> json,
  CanvasGraph graph,
  PipelinePhases pipelinePhases,
  ArchNodeParamUpdater updateArchNode,
  DagNodeParamUpdater updateDagNode,
) {
  final applied = <String>[];
  final skipped = <String>[];

  void applyArch(String jsonKey, String nirType, String paramKey) {
    if (!json.containsKey(jsonKey)) {
      skipped.add('$jsonKey: not present in imported JSON');
      return;
    }
    final matches = graph.nodes
        .where((n) => (n.nirType ?? n.componentId) == nirType)
        .toList();
    if (matches.isEmpty) {
      skipped.add('$jsonKey: no $nirType node found');
      return;
    }
    if (matches.length > 1) {
      skipped.add(
        '$jsonKey: ambiguous - ${matches.length} $nirType nodes found',
      );
      return;
    }
    updateArchNode(matches.single.id, {paramKey: json[jsonKey]});
    applied.add('$jsonKey -> $nirType.$paramKey');
  }

  void applyDag(String jsonKey, PipelineDagNodeType type, String paramKey) {
    if (!json.containsKey(jsonKey)) {
      skipped.add('$jsonKey: not present in imported JSON');
      return;
    }
    final matches = pipelinePhases.train.nodes
        .where((n) => n.type == type)
        .toList();
    if (matches.isEmpty) {
      skipped.add('$jsonKey: no ${type.name} node found in Train DAG');
      return;
    }
    if (matches.length > 1) {
      skipped.add(
        '$jsonKey: ambiguous - ${matches.length} ${type.name} nodes found '
        'in Train DAG',
      );
      return;
    }
    updateDagNode(PipelinePhaseId.train, matches.single.id, {
      paramKey: json[jsonKey],
    });
    applied.add('$jsonKey -> ${type.name}.$paramKey');
  }

  applyArch('nb_hidden', 'cnl.RSynaptic', 'n_neurons');
  applyArch('alpha_r', 'cnl.RSynaptic', 'alpha');
  applyArch('beta_r', 'cnl.RSynaptic', 'beta');
  applyArch('alpha_out', 'cnl.Synaptic', 'alpha');
  applyArch('beta_out', 'cnl.Synaptic', 'beta');

  applyDag('lr', PipelineDagNodeType.adamOptimiser, 'lr');
  applyDag('slope', PipelineDagNodeType.surrogateBackward, 'slope');
  applyDag('reg_l1', PipelineDagNodeType.l1SpikeReg, 'weight');
  applyDag('reg_l2', PipelineDagNodeType.l2SpikeReg, 'weight');

  return ConfigImportReport(applied: applied, skipped: skipped);
}
