import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';

/// The one-line "key parameter" summary shown under a node's title on every
/// canvas.
///
/// The Train/Eval cards have carried this second line for a while (`lr: 0.001`,
/// `steps: 25`) while the Architecture cards showed only a title, which is one
/// of the reasons the model canvas read as a different kind of surface. Both
/// canvases now source their subtitle from here.

// ── Pipeline (Train / Eval) ─────────────────────────────────────────────────

/// Moved verbatim from `pipeline_phase_canvas.dart`, where it was a private
/// `_nodeKeyParam`.
String? pipelineNodeKeyParam(PipelineDagNode node) {
  final Map<String, dynamic> p = node.parameters;
  return switch (node.type) {
    PipelineDagNodeType.dataLoader ||
    PipelineDagNodeType.testLoader => 'batch: ${p['batch_size'] ?? 32}',
    PipelineDagNodeType.timeLoop ||
    PipelineDagNodeType.lavaProcessGraph => 'steps: ${p['num_steps'] ?? 25}',
    PipelineDagNodeType.lavaSim => 'steps: ${p['num_steps'] ?? 25}',
    PipelineDagNodeType.adamOptimiser ||
    PipelineDagNodeType.sgdOptimiser ||
    PipelineDagNodeType.adamwOptimiser ||
    PipelineDagNodeType.rmspropOptimiser => 'lr: ${p['lr'] ?? '—'}',
    PipelineDagNodeType.stepLR =>
      'step: ${p['step_size'] ?? 10} · γ: ${p['gamma'] ?? 0.1}',
    PipelineDagNodeType.cosineAnnealingLR => 'T: ${p['T_max'] ?? 50}',
    PipelineDagNodeType.exponentialLR => 'γ: ${p['gamma'] ?? 0.95}',
    PipelineDagNodeType.spikeEncoder =>
      '${p['encoding'] ?? 'rate'} · ${p['time_window'] ?? 25}t',
    PipelineDagNodeType.spikeGenerator =>
      '${p['n_timesteps'] ?? 100}t · ${p['pattern'] ?? 'isi_regular'}',
    PipelineDagNodeType.accuracyMetric => 'top-${p['top_k'] ?? 1}',
    PipelineDagNodeType.f1Score => '${p['average'] ?? 'macro'}',
    PipelineDagNodeType.mseCountLoss => 'cr: ${p['correct_rate'] ?? 0.8}',
    PipelineDagNodeType.crossEntropyLoss =>
      'smooth: ${p['label_smoothing'] ?? 0.0}',
    PipelineDagNodeType.nirExporter ||
    PipelineDagNodeType.pyExporter => '${p['filename'] ?? ''}',
    // The bundle marker is on the card because it is the difference between
    // converting a model and being able to deploy it, and it is otherwise
    // invisible until the notebook runs.
    PipelineDagNodeType.akidaExporter =>
      '${p['filename'] ?? 'model.fbz'} · ${p['weight_bits'] ?? 4}-bit'
          '${p['deploy_bundle'] == false ? '' : ' · bundle'}',
    PipelineDagNodeType.forwardPass => null,
    PipelineDagNodeType.surrogateBackward =>
      '${p['function'] ?? 'fast_sigmoid'} · slope: ${p['slope'] ?? 25.0}',
    PipelineDagNodeType.l1SpikeReg => 'λ₁: ${p['weight'] ?? 1e-5}',
    PipelineDagNodeType.l2SpikeReg => 'λ₂: ${p['weight'] ?? 1e-5}',
    _ => null,
  };
}

// ── Architecture ────────────────────────────────────────────────────────────

/// Parameters worth putting on a card, most telling first, with the short
/// label each renders under.
///
/// Driven off the node type's own parameter list rather than a per-type
/// switch, so a new NIR type gets a sensible subtitle without another branch
/// here. At most two fields are shown — the card is 150px wide.
const List<({String key, String label})> _nirSubtitleFields =
    <({String key, String label})>[
      (key: 'n_neurons', label: 'n'),
      (key: 'size', label: 'n'),
      (key: 'num_features', label: 'n'),
      (key: 'tau', label: 'τ'),
      (key: 'tau_mem', label: 'τm'),
      (key: 'threshold', label: 'θ'),
      (key: 'beta', label: 'β'),
      (key: 'p', label: 'p'),
      (key: 'scale', label: '×'),
      (key: 'delay', label: 'Δt'),
      (key: 'kernel_size', label: 'k'),
    ];

/// Key-parameter line for an Architecture (NIR) node.
///
/// Reads the node's own edited value where it has one and falls back to the
/// type's default, so a freshly-dropped node shows the same thing the
/// property panel does. Returns null when nothing informative is available.
String? nirNodeKeyParam(CanvasNode node, NirNodeType? type) {
  Object? valueOf(String key) {
    final Object? edited = node.parameters[key];
    if (edited != null && edited.toString().isNotEmpty) return edited;
    final NirParameterDef? def = type?.parameters
        .cast<NirParameterDef?>()
        .firstWhere((NirParameterDef? d) => d?.name == key, orElse: () => null);
    return def?.defaultValue;
  }

  // Linear/Affine and the conv family are shape-defined; their weight
  // dimensions say far more than any single scalar.
  final Object? rows = valueOf('rows');
  final Object? cols = valueOf('cols');
  if (rows != null && cols != null) {
    return '${_fmt(cols)}→${_fmt(rows)}';
  }
  final Object? weightShape = valueOf('weight_shape');
  if (weightShape != null && weightShape.toString().isNotEmpty) {
    return '[${weightShape.toString().replaceAll(' ', '')}]';
  }

  final List<String> parts = <String>[];
  for (final ({String key, String label}) field in _nirSubtitleFields) {
    if (parts.length >= 2) break;
    final Object? value = valueOf(field.key);
    if (value == null) continue;
    parts.add('${field.label}: ${_fmt(value)}');
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Compact number formatting: no trailing `.0`, no long float tails.
String _fmt(Object value) {
  if (value is int) return value.toString();
  final num? n = value is num ? value : num.tryParse(value.toString());
  if (n == null) return value.toString();
  if (n == n.roundToDouble() && n.abs() < 1e6) return n.toInt().toString();
  final String s = n.toStringAsPrecision(3);
  return s.contains('e') ? s : s.replaceFirst(RegExp(r'0+$'), '');
}
