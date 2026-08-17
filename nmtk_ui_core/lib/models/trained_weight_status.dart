/// Where a network's weights came from on the way to a target.
///
/// CNL stores tensor *shape* only, so anything built from the spec alone carries
/// an all-zero weight matrix — correct shape, correct synapse count, every value
/// 0.0. Both the PYNQ deploy payload and the software simulators overlay the
/// trained `.nir` graph to fix that, and both report the outcome with this shape.
class TrainedWeightStatus {
  final bool applied;
  final String? sourceNode;
  final List<int>? shape;
  final int nonzero;
  final String detail;

  const TrainedWeightStatus({
    required this.applied,
    required this.detail,
    this.sourceNode,
    this.shape,
    this.nonzero = 0,
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
    );
  }
}
