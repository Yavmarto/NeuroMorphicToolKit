/// Quantization analysis report from the backend.
class QuantizationReport {
  final List<int> bitWidths;
  final List<double> accuracyDrops;
  final List<double> sparsity;

  const QuantizationReport({
    required this.bitWidths,
    required this.accuracyDrops,
    required this.sparsity,
  });

  factory QuantizationReport.fromJson(Map<String, dynamic> json) {
    return QuantizationReport(
      bitWidths: (json['bit_widths'] as List)
          .map((v) => (v as num).toInt())
          .toList(),
      accuracyDrops: (json['accuracy_drops'] as List)
          .map((v) => (v as num).toDouble())
          .toList(),
      sparsity: (json['sparsity'] as List)
          .map((v) => (v as num).toDouble())
          .toList(),
    );
  }
}
