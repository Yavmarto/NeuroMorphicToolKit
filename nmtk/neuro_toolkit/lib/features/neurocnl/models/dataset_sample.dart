/// One evaluation sample from a workspace, already shaped as an input frame.
///
/// A fixed-function overlay consumes a whole frame — one word per input neuron —
/// and the only stimulus the app could offer before this was a hand-typed list
/// of spike indices, which is not a usable way to present 784 pixels. The
/// evaluation set the model was scored against is already in the workspace, so
/// the board runs the same data rather than something reconstructed by hand.
///
/// [inputSpikes] is binary because that is the only input the overlay accepts —
/// a pixel either spikes or it does not. That is coarser than the greyscale the
/// model trained on, which is why board accuracy sits below the simulation
/// figure and why the UI says so next to the sample.
class DatasetSample {
  const DatasetSample({
    required this.filename,
    required this.sampleIndex,
    required this.sampleCount,
    required this.inputWidth,
    required this.inputSpikes,
    required this.spikeCount,
    this.label,
  });

  factory DatasetSample.fromJson(Map<String, dynamic> json) {
    final spikes = (json['input_spikes'] as List<dynamic>? ?? const <dynamic>[])
        .map((value) => (value as num).toInt())
        .toList(growable: false);
    return DatasetSample(
      filename: json['filename'] as String? ?? '',
      sampleIndex: (json['sample_index'] as num?)?.toInt() ?? 0,
      sampleCount: (json['sample_count'] as num?)?.toInt() ?? 0,
      inputWidth: (json['input_width'] as num?)?.toInt() ?? spikes.length,
      inputSpikes: spikes,
      spikeCount:
          (json['spike_count'] as num?)?.toInt() ??
          spikes.fold<int>(0, (sum, value) => sum + value),
      label: (json['label'] as num?)?.toInt(),
    );
  }

  final String filename;
  final int sampleIndex;
  final int sampleCount;
  final int inputWidth;

  /// One word per input neuron, 1 where it spikes.
  final List<int> inputSpikes;
  final int spikeCount;

  /// Null when the dataset carries no labels, so nothing claims a ground truth
  /// it does not have.
  final int? label;

  /// Side length when the frame is a square image, else null. Used only to
  /// choose a preview shape — a network whose input is not an image still runs.
  int? get previewSide {
    if (inputWidth <= 0) return null;
    final side = _integerSqrt(inputWidth);
    return side * side == inputWidth ? side : null;
  }

  static int _integerSqrt(int value) {
    var guess = 0;
    while ((guess + 1) * (guess + 1) <= value) {
      guess++;
    }
    return guess;
  }
}
