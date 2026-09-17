/// Result returned by the crossbar-export endpoint.
class CrossbarExportResult {
  final List<List<double>> quantizedWeights;
  final int bitWidth;
  final double scaleFactor;
  final double zeroPoint;
  final double sparsity;

  const CrossbarExportResult({
    required this.quantizedWeights,
    required this.bitWidth,
    required this.scaleFactor,
    required this.zeroPoint,
    required this.sparsity,
  });

  factory CrossbarExportResult.fromJson(Map<String, dynamic> json) {
    return CrossbarExportResult(
      quantizedWeights: (json['quantized_weights'] as List)
          .map(
            (row) => (row as List).map((v) => (v as num).toDouble()).toList(),
          )
          .toList(),
      bitWidth: json['bit_width'] as int,
      scaleFactor: (json['scale_factor'] as num).toDouble(),
      zeroPoint: (json['zero_point'] as num).toDouble(),
      sparsity: (json['sparsity'] as num).toDouble(),
    );
  }
}
