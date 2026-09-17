/// Where a network's weights came from on the way to a target.
///
/// CNL stores tensor *shape* only, so anything built from the spec alone carries
/// an all-zero weight matrix — correct shape, correct synapse count, every value
/// 0.0. Both the PYNQ deploy payload and the software simulators overlay the
/// trained `.nir` graph to fix that, and both report the outcome with this shape.
/// One weight matrix's shape and fill, so sparsity can be read per layer.
///
/// [TrainedWeightStatus.shape] describes only the *first* matrix while its
/// `nonzero` counts every layer, so dividing one by the other overstates
/// density — on a multi-layer network it can exceed 1.0. These per-layer
/// entries are the honest numbers.
class TrainedWeightLayer {
  /// Name of the node in the trained `.nir` file this matrix came from.
  final String name;

  /// `[rows, cols]` of this matrix.
  final List<int> shape;
  final int nonzero;

  const TrainedWeightLayer({
    required this.name,
    required this.shape,
    required this.nonzero,
  });

  /// Number of weight slots this matrix holds, zero if the shape is malformed.
  int get synapseCount =>
      shape.length < 2 ? 0 : shape.fold(1, (product, dim) => product * dim);

  /// Fraction of this matrix that is non-zero, 0.0 when the shape is unusable.
  double get density {
    final total = synapseCount;
    return total <= 0 ? 0.0 : nonzero / total;
  }

  factory TrainedWeightLayer.fromJson(Map<String, dynamic> json) {
    return TrainedWeightLayer(
      name: json['name'] as String? ?? '',
      shape:
          (json['shape'] as List<dynamic>?)
              ?.map((value) => (value as num).toInt())
              .toList(growable: false) ??
          const <int>[],
      nonzero: (json['nonzero'] as num?)?.toInt() ?? 0,
    );
  }
}

class TrainedWeightStatus {
  final bool applied;
  final String? sourceNode;

  /// Shape of the **first** weight matrix only. For anything per-layer, and for
  /// any sparsity figure, read [layers] instead.
  final List<int>? shape;

  /// Non-zero weights summed across **every** layer.
  final int nonzero;
  final String detail;

  /// Per-layer shape and fill. Empty on results from a backend that predates
  /// the breakdown — fall back to [shape]/[nonzero], labelled as layer 1.
  final List<TrainedWeightLayer> layers;

  const TrainedWeightStatus({
    required this.applied,
    required this.detail,
    this.sourceNode,
    this.shape,
    this.nonzero = 0,
    this.layers = const [],
  });

  /// True when weights were applied but every one of them is zero — a model
  /// exported before training ran. Deploys, computes nothing.
  bool get isAllZero => applied && nonzero == 0;

  /// True when this network will actually compute something.
  bool get hasRealWeights => applied && nonzero > 0;

  factory TrainedWeightStatus.fromJson(Map<String, dynamic> json) {
    return TrainedWeightStatus(
      applied: json['applied'] as bool? ?? false,
      sourceNode: json['source_node'] as String?,
      shape: (json['shape'] as List<dynamic>?)
          ?.map((value) => (value as num).toInt())
          .toList(growable: false),
      nonzero: (json['nonzero'] as num?)?.toInt() ?? 0,
      detail: json['detail'] as String? ?? '',
      layers:
          (json['layers'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(TrainedWeightLayer.fromJson)
              .toList(growable: false) ??
          const <TrainedWeightLayer>[],
    );
  }
}
