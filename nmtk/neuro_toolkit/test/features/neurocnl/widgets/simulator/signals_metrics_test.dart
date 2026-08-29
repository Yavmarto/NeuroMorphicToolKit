import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/simulator/signals_metrics.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  group('resolveDtMs', () {
    test('falls back to 1ms when metadata carries no usable dt', () {
      expect(resolveDtMs(const {}), 1.0);
      expect(resolveDtMs(const {'dt_ms': 0}), 1.0);
      expect(resolveDtMs(const {'dt_ms': -3}), 1.0);
      expect(resolveDtMs(const {'dt_ms': 'half'}), 1.0);
    });

    test('reads the run\'s own timestep', () {
      expect(resolveDtMs(const {'dt_ms': 0.5}), 0.5);
      expect(resolveDtMs(const {'dt_ms': 2}), 2.0);
    });
  });

  group('populationStats', () {
    test('averages over the whole population, not just the active neurons', () {
      // One neuron firing 10 times out of 100 possible slots. Averaged over
      // four neurons that is 25 Hz, not the 100 Hz an active-only mean gives.
      final stats = populationStats(
        {'0': List<int>.generate(10, (i) => i)},
        timesteps: 100,
        dtMs: 1.0,
        neuronCount: 4,
      );
      expect(stats.spikeCount, 10);
      expect(stats.activeNeurons, 1);
      expect(stats.neuronCount, 4);
      expect(stats.silentNeurons, 3);
      expect(stats.meanRateHz, closeTo(25.0, 1e-9));
    });

    test('honours dt_ms — a half-millisecond step doubles the rate', () {
      final oneMs = populationStats(
        {
          '0': const [0, 1, 2, 3],
        },
        timesteps: 100,
        dtMs: 1.0,
        neuronCount: 1,
      );
      final halfMs = populationStats(
        {
          '0': const [0, 1, 2, 3],
        },
        timesteps: 100,
        dtMs: 0.5,
        neuronCount: 1,
      );
      expect(oneMs.meanRateHz, closeTo(40.0, 1e-9));
      expect(halfMs.meanRateHz, closeTo(80.0, 1e-9));
    });

    test('never divides by fewer neurons than actually fired', () {
      // A stale or missing neuron_count must not inflate the rate past what
      // the spike data itself implies.
      final stats = populationStats(
        {
          '0': const [1],
          '1': const [2],
          '2': const [3],
        },
        timesteps: 10,
        dtMs: 1.0,
        neuronCount: 1,
      );
      expect(stats.neuronCount, 3);
    });

    test('an empty or fully silent population reports zero, not NaN', () {
      final empty = populationStats(const {}, timesteps: 10, dtMs: 1.0);
      expect(empty.spikeCount, 0);
      expect(empty.meanRateHz, 0.0);

      final silent = populationStats(
        {'0': const <int>[], '1': const <int>[]},
        timesteps: 10,
        dtMs: 1.0,
      );
      expect(silent.activeNeurons, 0);
      expect(silent.meanRateHz, 0.0);
    });

    test('a zero-length run reports zero rather than dividing by zero', () {
      final stats = populationStats(
        {
          '0': const [0],
        },
        timesteps: 0,
        dtMs: 1.0,
        neuronCount: 1,
      );
      expect(stats.meanRateHz, 0.0);
    });
  });

  group('rasterRows', () {
    test('keeps silent neurons as empty rows so row index == neuron index', () {
      final rows = rasterRows(
        {
          '0': const [1],
          '3': const [2],
        },
        dtMs: 1.0,
        neuronCount: 5,
      );
      expect(rows.length, 5);
      expect(rows[0], [1.0]);
      expect(rows[1], isEmpty);
      expect(rows[2], isEmpty);
      expect(rows[3], [2.0]);
      expect(rows[4], isEmpty);
    });

    test('scales timesteps into milliseconds', () {
      final rows = rasterRows(
        {
          '0': const [0, 2, 4],
        },
        dtMs: 0.5,
        neuronCount: 1,
      );
      expect(rows.single, [0.0, 1.0, 2.0]);
    });

    test('grows past a stale neuron count rather than dropping neurons', () {
      final rows = rasterRows(
        {
          '7': const [1],
        },
        dtMs: 1.0,
        neuronCount: 2,
      );
      expect(rows.length, 8);
      expect(rows[7], [1.0]);
    });

    test('ignores keys that are not neuron indices', () {
      final rows = rasterRows({
        '0': const [1],
        'total': const [9],
      }, dtMs: 1.0);
      expect(rows.length, 1);
    });
  });

  group('TrainedWeightLayer.density', () {
    test('is the filled fraction of the matrix', () {
      const layer = TrainedWeightLayer(
        name: 'fc1',
        shape: [10, 10],
        nonzero: 25,
      );
      expect(layer.synapseCount, 100);
      expect(layer.density, 0.25);
    });

    test('returns zero rather than NaN for a malformed shape', () {
      expect(
        const TrainedWeightLayer(name: 'x', shape: [], nonzero: 5).density,
        0.0,
      );
      expect(
        const TrainedWeightLayer(name: 'x', shape: [0, 8], nonzero: 5).density,
        0.0,
      );
    });
  });
}
