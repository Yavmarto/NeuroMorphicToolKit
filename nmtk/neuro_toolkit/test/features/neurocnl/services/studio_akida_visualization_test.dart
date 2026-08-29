import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_akida_deploy_service.dart';

Map<String, dynamic> _arrayJson({
  required String dtype,
  required List<int> shape,
  required Uint8List bytes,
}) => <String, dynamic>{
  'encoding': 'zlib+base64',
  'dtype': dtype,
  'shape': shape,
  'data': base64Encode(const ZLibEncoder().encodeBytes(bytes)),
};

void main() {
  test('decodes exact int8 weights and float32 mean activity', () {
    final floats = ByteData(8)
      ..setFloat32(0, 1.5, Endian.little)
      ..setFloat32(4, 2.5, Endian.little);
    final result = StudioAkidaModelVisualization.fromJson(<String, dynamic>{
      'modelId': 'model-1',
      'mode': 'benchmark',
      'layers': <Map<String, dynamic>>[
        <String, dynamic>{
          'index': 1,
          'name': 'Hidden',
          'outputShape': <int>[2],
          'weightShape': <int>[2, 2],
          'weightBits': 8,
          'visualizable': true,
        },
      ],
      'layerIndex': 1,
      'layerName': 'Hidden',
      'sampleCount': 1000,
      'available': true,
      'activity': _arrayJson(
        dtype: '<f4',
        shape: <int>[2],
        bytes: floats.buffer.asUint8List(),
      ),
      'weights': _arrayJson(
        dtype: '|i1',
        shape: <int>[2, 2],
        bytes: Uint8List.fromList(<int>[1, 254, 3, 252]),
      ),
      'weightBits': 8,
      'provenance': 'akida_software_replay',
      'relatedRuntimeTarget': 'hardware',
      'hardwareVerified': false,
    });

    expect(result.activity!.values, <double>[1.5, 2.5]);
    expect(result.weights!.values, <double>[1, -2, 3, -4]);
    expect(result.weightBits, 8);
    expect(result.hardwareVerified, isFalse);
  });

  test('rejects an array whose shape does not match its bytes', () {
    expect(
      () => StudioAkidaCompressedArray.fromJson(
        _arrayJson(
          dtype: '|u1',
          shape: <int>[3],
          bytes: Uint8List.fromList(<int>[1, 2]),
        ),
      ),
      throwsFormatException,
    );
  });

  test('decodes int32 activity from a layer without output activations', () {
    final values = ByteData(8)
      ..setInt32(0, 1, Endian.little)
      ..setInt32(4, -2, Endian.little);

    final result = StudioAkidaCompressedArray.fromJson(
      _arrayJson(
        dtype: '<i4',
        shape: <int>[2],
        bytes: values.buffer.asUint8List(),
      ),
    );

    expect(result.values, <double>[1, -2]);
  });
}
