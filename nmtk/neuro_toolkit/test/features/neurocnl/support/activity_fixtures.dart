import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Builds a minimal, spec-valid NPY v1 buffer for a float32 array with the
/// given [shape], filled row-major (C order) from [data].
Uint8List buildNpyV1({required List<int> shape, required List<double> data}) {
  final shapeStr = shape.length == 1
      ? '(${shape[0]},)'
      : '(${shape.join(', ')})';
  final headerDict =
      "{'descr': '<f4', 'fortran_order': False, 'shape': $shapeStr, }";

  // NPY v1 requires the total header (magic + version + header-length field
  // + header dict + trailing newline) to be a multiple of 16 bytes, padded
  // with spaces before the final '\n'.
  const prefixLen = 10; // 6-byte magic + 2-byte version + 2-byte header-len
  final unpaddedTotal = prefixLen + headerDict.length + 1;
  final pad = (16 - unpaddedTotal % 16) % 16;
  final paddedHeader = '$headerDict${' ' * pad}\n';
  final headerBytes = ascii.encode(paddedHeader);
  final headerLen = headerBytes.length;

  final builder = BytesBuilder();
  builder.add(const [0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59]); // \x93NUMPY
  builder.add(const [1, 0]); // version 1.0
  builder.add([headerLen & 0xff, (headerLen >> 8) & 0xff]); // header len, LE
  builder.add(headerBytes);
  builder.add(Float32List.fromList(data).buffer.asUint8List());
  return builder.toBytes();
}

/// Packs per-bucket NPY buffers into the `<bucket>_spikes.npy` zip layout the
/// backend serves from `/training/activity`.
Uint8List buildActivityZip(Map<String, Uint8List> npyFilesByBucket) {
  final archive = Archive();
  npyFilesByBucket.forEach((bucket, bytes) {
    archive.addFile(ArchiveFile('${bucket}_spikes.npy', bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// A `(timesteps, neurons)` spike export where neuron *n* fires on every
/// timestep that is a multiple of `n + 1`, so every tile has a distinct trail.
Uint8List buildSpikeActivityZip({
  String bucket = 'hidden',
  int timesteps = 25,
  int neurons = 4,
}) {
  final data = <double>[];
  for (var t = 0; t < timesteps; t++) {
    for (var n = 0; n < neurons; n++) {
      data.add(t % (n + 1) == 0 ? 1.0 : 0.0);
    }
  }
  return buildActivityZip({
    bucket: buildNpyV1(shape: [timesteps, neurons], data: data),
  });
}
