import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/npy_parser.dart';

import '../support/activity_fixtures.dart';

void main() {
  group('NpyParser.parseNpy', () {
    test('parses a (4, 3) shaped float32 array', () {
      // Row-major (timesteps=4, neurons=3):
      //   t=0: [1, 0, 0]
      //   t=1: [0, 1, 0]
      //   t=2: [1, 1, 0]
      //   t=3: [0, 0, 1]
      final data = <double>[
        1, 0, 0, //
        0, 1, 0, //
        1, 1, 0, //
        0, 0, 1, //
      ];
      final bytes = buildNpyV1(shape: [4, 3], data: data);

      final array = NpyParser.parseNpy(bytes);

      expect(array.shape, [4, 3]);
      expect(array.data.length, 12);
      expect(array.data.toList(), data);
    });

    test('parses a 1-D shape tuple with a trailing comma, e.g. (5,)', () {
      final bytes = buildNpyV1(shape: [5], data: [1, 2, 3, 4, 5]);

      final array = NpyParser.parseNpy(bytes);

      expect(array.shape, [5]);
      expect(array.data.toList(), [1, 2, 3, 4, 5]);
    });

    test('rejects a buffer with a bad magic prefix', () {
      final bytes = buildNpyV1(shape: [1, 1], data: [1]);
      bytes[1] = 0x00; // corrupt magic

      expect(() => NpyParser.parseNpy(bytes), throwsException);
    });
  });

  group('NpyParser.extractSpikeRaster', () {
    test('reshapes a (4, 3) timesteps-by-neurons array into a per-neuron '
        'spike-time raster with exactly one key per neuron', () {
      final data = <double>[
        1, 0, 0, // t=0 -> neuron_0 spikes
        0, 1, 0, // t=1 -> neuron_1 spikes
        1, 1, 0, // t=2 -> neuron_0 and neuron_1 spike
        0, 0, 1, // t=3 -> neuron_2 spikes
      ];
      final array = NpyArray(
        data: Float32List.fromList(data),
        shape: const [4, 3],
      );

      final raster = NpyParser.extractSpikeRaster(array);

      expect(raster.keys.toSet(), {'neuron_0', 'neuron_1', 'neuron_2'});
      expect(raster['neuron_0'], [0.0, 2.0]);
      expect(raster['neuron_1'], [1.0, 2.0]);
      expect(raster['neuron_2'], [3.0]);
    });

    test('scales spike times by dtMs', () {
      final data = <double>[1, 0, 0, 1];
      final array = NpyArray(
        data: Float32List.fromList(data),
        shape: const [2, 2],
      );

      final raster = NpyParser.extractSpikeRaster(array, dtMs: 2.5);

      expect(raster['neuron_0'], [0.0]);
      expect(raster['neuron_1'], [2.5]);
    });

    test('treats values at or below 0.5 as no-spike (binary threshold)', () {
      // t=0: [0.5, 0.49] -> neither at/below-threshold value spikes.
      // t=1: [0.51, 0.0] -> only neuron_0 (0.51 > 0.5) spikes.
      final data = <double>[0.5, 0.49, 0.51, 0.0];
      final array = NpyArray(
        data: Float32List.fromList(data),
        shape: const [2, 2],
      );

      final raster = NpyParser.extractSpikeRaster(array);

      expect(raster['neuron_0'], [1.0]);
      expect(raster['neuron_1'], isEmpty);
    });

    test('rejects arrays that are not 2-D', () {
      final array = NpyArray(
        data: Float32List.fromList([1, 2, 3]),
        shape: const [3],
      );

      expect(() => NpyParser.extractSpikeRaster(array), throwsException);
    });

    test('rejects a 3-D (batch, timesteps, neurons) array with a clear, '
        'catchable exception instead of silently misreading the batch axis '
        'as a neuron/timestep dimension', () {
      // Shape of the feed-forward (TinySnn/NirSnn) training path's
      // activity export, e.g. (batch=2, timesteps=4, neurons=3).
      final array = NpyArray(
        data: Float32List.fromList(List<double>.filled(24, 0)),
        shape: const [2, 4, 3],
      );

      expect(
        () => NpyParser.extractSpikeRaster(array),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('NpyParser.selectBatchSample', () {
    test('extracts batch index 0 from a (batch, timesteps, neurons) array', () {
      // batch=2, timesteps=2, neurons=3.
      // Batch 0: t=0 -> [1,0,0], t=1 -> [0,1,0]
      // Batch 1: t=0 -> [0,0,1], t=1 -> [1,1,1]
      final data = <double>[
        1, 0, 0, 0, 1, 0, // batch 0
        0, 0, 1, 1, 1, 1, // batch 1
      ];
      final array = NpyArray(
        data: Float32List.fromList(data),
        shape: const [2, 2, 3],
      );

      final sample = NpyParser.selectBatchSample(array);

      expect(sample.shape, [2, 3]);
      expect(sample.data.toList(), [1, 0, 0, 0, 1, 0]);
    });

    test('extracts a non-zero batchIndex', () {
      final data = <double>[
        1, 0, 0, 0, 1, 0, // batch 0
        0, 0, 1, 1, 1, 1, // batch 1
      ];
      final array = NpyArray(
        data: Float32List.fromList(data),
        shape: const [2, 2, 3],
      );

      final sample = NpyParser.selectBatchSample(array, batchIndex: 1);

      expect(sample.shape, [2, 3]);
      expect(sample.data.toList(), [0, 0, 1, 1, 1, 1]);
    });

    test('rejects arrays that are not 3-D', () {
      final array = NpyArray(
        data: Float32List.fromList([1, 0, 0, 1]),
        shape: const [2, 2],
      );

      expect(
        () => NpyParser.selectBatchSample(array),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects an out-of-range batchIndex', () {
      final array = NpyArray(
        data: Float32List.fromList([1, 0, 0, 1, 0, 0]),
        shape: const [1, 2, 3],
      );

      expect(
        () => NpyParser.selectBatchSample(array, batchIndex: 5),
        throwsA(isA<Exception>()),
      );
    });

    test('combined with extractSpikeRaster, renders a batch-0 raster from a '
        '3-D feed-forward export', () {
      final data = <double>[
        1, 0, 0, 0, 1, 0, // batch 0
        0, 0, 1, 1, 1, 1, // batch 1
      ];
      final array = NpyArray(
        data: Float32List.fromList(data),
        shape: const [2, 2, 3],
      );

      final raster = NpyParser.extractSpikeRaster(
        NpyParser.selectBatchSample(array),
      );

      expect(raster['neuron_0'], [0.0]);
      expect(raster['neuron_1'], [1.0]);
      expect(raster['neuron_2'], isEmpty);
    });
  });

  group('NpyParser.extractActivityArrays', () {
    test('recovers each *_spikes.npy bucket with its parsed shape', () {
      final hidden = buildNpyV1(
        shape: [4, 3],
        data: List<double>.filled(12, 0),
      );
      final output = buildNpyV1(shape: [4, 2], data: List<double>.filled(8, 0));
      final zipBytes = buildActivityZip({'hidden': hidden, 'output': output});

      final arrays = NpyParser.extractActivityArrays(zipBytes);

      expect(arrays.keys.toSet(), {'hidden', 'output'});
      expect(arrays['hidden']!.shape, [4, 3]);
      expect(arrays['output']!.shape, [4, 2]);
    });
  });
}
