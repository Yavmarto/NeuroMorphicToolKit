/// Request payload for the crossbar-export endpoint.
class CrossbarExportRequest {
  final List<List<double>> learnedWeights;
  final int bitWidth;
  final String format;

  const CrossbarExportRequest({
    required this.learnedWeights,
    this.bitWidth = 8,
    this.format = 'json',
  });

  Map<String, dynamic> toJson() => {
    'learned_weights': learnedWeights,
    'bit_width': bitWidth,
    'format': format,
  };
}
