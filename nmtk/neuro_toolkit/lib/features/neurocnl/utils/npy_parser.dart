import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// A parsed NPY array: its float payload plus the shape declared in the
/// NPY v1 header (e.g. `(256, 40)` for a `(timesteps, neurons)` export).
class NpyArray {
  /// Flattened row-major (C order) float data.
  final Float32List data;

  /// Array shape as declared in the NPY header, e.g. `[256, 40]`.
  final List<int> shape;

  const NpyArray({required this.data, required this.shape});
}

/// Minimal NPY v1 binary parser
class NpyParser {
  /// Parses a full NPY v1 buffer into its data and declared [shape].
  static NpyArray parseNpy(Uint8List bytes) {
    if (bytes.length < 10) throw Exception('Invalid NPY: too short');

    // Check magic string \x93NUMPY
    if (bytes[0] != 0x93 ||
        bytes[1] != 0x4e ||
        bytes[2] != 0x55 ||
        bytes[3] != 0x4d ||
        bytes[4] != 0x50 ||
        bytes[5] != 0x59) {
      throw Exception('Invalid NPY magic');
    }

    final majorVersion = bytes[6];
    if (majorVersion != 1) {
      throw Exception('Unsupported NPY version');
    }

    // header length in little endian
    final headerLen = bytes[8] | (bytes[9] << 8);
    final headerEnd = 10 + headerLen;

    if (bytes.length < headerEnd) throw Exception('Invalid NPY header length');

    final headerStr = ascii.decode(
      bytes.sublist(10, headerEnd),
      allowInvalid: true,
    );
    final shape = _parseShape(headerStr);

    final dataBytes = bytes.sublist(headerEnd);
    final floatData = Float32List.view(
      dataBytes.buffer,
      dataBytes.offsetInBytes,
      dataBytes.lengthInBytes ~/ 4,
    );

    return NpyArray(data: floatData, shape: shape);
  }

  /// Extracts the `shape: (a, b, ...)` tuple out of an NPY v1 header dict
  /// literal, e.g. `{'descr': '<f4', 'fortran_order': False, 'shape': (256, 40), }`.
  static List<int> _parseShape(String header) {
    final match = RegExp(r"'shape'\s*:\s*\(([^)]*)\)").firstMatch(header);
    if (match == null) {
      throw Exception('Invalid NPY header: no shape field found');
    }
    final inner = match.group(1)!.trim();
    if (inner.isEmpty) return const <int>[];
    return inner
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map(int.parse)
        .toList(growable: false);
  }

  /// Backwards-compatible float-only accessor — parses an NPY buffer and
  /// discards the shape.
  static Float32List parseNpyFloat32(Uint8List bytes) => parseNpy(bytes).data;

  /// Unzips a training-activity export and returns each `*_spikes.npy`
  /// bucket (e.g. `"hidden"`, `"output"`) as a shape-aware [NpyArray].
  static Map<String, NpyArray> extractActivityArrays(Uint8List zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final arrays = <String, NpyArray>{};

    for (final file in archive) {
      if (file.isFile && file.name.endsWith('_spikes.npy')) {
        final layerName = file.name.replaceAll('_spikes.npy', '');
        final data = file.content as List<int>;
        arrays[layerName] = parseNpy(Uint8List.fromList(data));
      }
    }
    return arrays;
  }

  /// Reshapes a `(timesteps, neurons)` [NpyArray] into a real per-neuron
  /// spike-time raster: `'neuron_$i' -> [spike times in ms]`.
  ///
  /// A spike is recorded for neuron `n` at timestep `t` when
  /// `data[t * neurons + n] > 0.5` — the snnTorch spiking layers this data
  /// comes from emit binary (0.0/1.0) spikes in the forward pass, so a 0.5
  /// threshold cleanly separates spike from no-spike.
  static Map<String, List<double>> extractSpikeRaster(
    NpyArray array, {
    double dtMs = 1.0,
  }) {
    if (array.shape.length != 2) {
      throw Exception(
        'extractSpikeRaster expects a 2D (timesteps, neurons) array, '
        'got shape ${array.shape}',
      );
    }
    final timesteps = array.shape[0];
    final neurons = array.shape[1];

    final raster = <String, List<double>>{
      for (var n = 0; n < neurons; n++) 'neuron_$n': <double>[],
    };

    for (var t = 0; t < timesteps; t++) {
      final rowOffset = t * neurons;
      for (var n = 0; n < neurons; n++) {
        if (array.data[rowOffset + n] > 0.5) {
          raster['neuron_$n']!.add(t * dtMs);
        }
      }
    }
    return raster;
  }

  /// Selects one batch sample out of a `(batch, timesteps, neurons)`
  /// [NpyArray] — the shape the feed-forward (`TinySnn`/`NirSnn`) training
  /// path exports, as opposed to the recurrent path's batch-less
  /// `(timesteps, neurons)` export — and returns it as a 2D
  /// `(timesteps, neurons)` [NpyArray] suitable for [extractSpikeRaster].
  ///
  /// Throws if [array] isn't 3-D or if [batchIndex] is out of range.
  static NpyArray selectBatchSample(NpyArray array, {int batchIndex = 0}) {
    if (array.shape.length != 3) {
      throw Exception(
        'selectBatchSample expects a 3D (batch, timesteps, neurons) array, '
        'got shape ${array.shape}',
      );
    }
    final batch = array.shape[0];
    final timesteps = array.shape[1];
    final neurons = array.shape[2];
    if (batchIndex < 0 || batchIndex >= batch) {
      throw Exception(
        'selectBatchSample: batchIndex $batchIndex out of range for batch '
        'size $batch',
      );
    }

    final sampleSize = timesteps * neurons;
    final offset = batchIndex * sampleSize;
    final sample = Float32List.sublistView(
      array.data,
      offset,
      offset + sampleSize,
    );
    return NpyArray(data: sample, shape: [timesteps, neurons]);
  }
}
