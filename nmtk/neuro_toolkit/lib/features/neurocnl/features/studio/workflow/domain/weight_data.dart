import 'dart:typed_data';

/// Parsed binary payload for notebook weight visualization.

class WeightData {
  final int nNeurons;
  final int nInputs;
  final int side;
  final double vmax;
  final Float32List weights; // flat: [nNeurons * nInputs]

  const WeightData({
    required this.nNeurons,
    required this.nInputs,
    required this.side,
    required this.vmax,
    required this.weights,
  });

  /// Parse the custom binary format written by the notebook weight visualizer:
  ///   bytes 0-3  : n_neurons (int32 LE)
  ///   bytes 4-7  : n_inputs  (int32 LE)
  ///   bytes 8-11 : side      (int32 LE)  √n_inputs
  ///   bytes 12-15: vmax      (float32 LE)
  ///   bytes 16+  : n_neurons × n_inputs float32 LE, row-major
  static WeightData? tryParse(Uint8List raw) {
    if (raw.length < 16) return null;
    final bd = raw.buffer.asByteData(raw.offsetInBytes);
    final nNeurons = bd.getInt32(0, Endian.little);
    final nInputs = bd.getInt32(4, Endian.little);
    final side = bd.getInt32(8, Endian.little);
    final vmax = bd.getFloat32(12, Endian.little);
    final expected = 16 + nNeurons * nInputs * 4;
    if (raw.length < expected || nNeurons <= 0 || nInputs <= 0 || side <= 0) {
      return null;
    }
    final weights = Float32List.view(
      raw.buffer,
      raw.offsetInBytes + 16,
      nNeurons * nInputs,
    );
    return WeightData(
      nNeurons: nNeurons,
      nInputs: nInputs,
      side: side,
      vmax: vmax,
      weights: weights,
    );
  }

  /// Return a copy of neuron [i]'s weight slice.
  Float32List neuronWeights(int i) =>
      Float32List.fromList(weights.sublist(i * nInputs, (i + 1) * nInputs));
}
