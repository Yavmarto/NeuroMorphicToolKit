import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/simulator.dart';

Map<String, dynamic> _payload({Map<String, dynamic>? extra}) => {
  'backend_name': 'snntorch_sim',
  'status': 'completed',
  'support_level': 'exact',
  'timesteps': 100,
  'duration_seconds': 0.25,
  'spikes': {
    'output': {
      '0': [1, 2, 3],
    },
  },
  'voltages': <String, dynamic>{},
  'warnings': <String>[],
  'nir_summary': {
    'node_count': 3,
    'edge_count': 2,
    'unsupported_nodes': <String>[],
  },
  'metadata': {'dt_ms': 1.0},
  ...?extra,
};

void main() {
  group('SimulatorRunResult.stimulus', () {
    test('is null when the backend predates stimulus capture', () {
      final result = SimulatorRunResult.fromJson(_payload());
      expect(result.stimulus, isNull);
      expect(result.spikes['output']!['0'], [1, 2, 3]);
    });

    test('parses the echoed stimulus', () {
      final result = SimulatorRunResult.fromJson(
        _payload(
          extra: {
            'stimulus': {
              'population': 'input',
              'neuron_count': 784,
              'generated': true,
              'truncated': false,
              'spikes': {
                '0': [0, 5],
                '7': [3],
              },
            },
          },
        ),
      );

      final stimulus = result.stimulus!;
      expect(stimulus.population, 'input');
      expect(stimulus.neuronCount, 784);
      expect(stimulus.generated, isTrue);
      expect(stimulus.truncated, isFalse);
      expect(stimulus.spikes['0'], [0, 5]);
      expect(stimulus.spikes['7'], [3]);
    });

    test('survives a stimulus object missing its optional fields', () {
      final result = SimulatorRunResult.fromJson(
        _payload(
          extra: {
            'stimulus': {'population': 'input', 'neuron_count': 4},
          },
        ),
      );
      expect(result.stimulus!.spikes, isEmpty);
      expect(result.stimulus!.truncated, isFalse);
    });

    test('ignores a stimulus field that is not an object', () {
      final result = SimulatorRunResult.fromJson(
        _payload(extra: {'stimulus': 'none'}),
      );
      expect(result.stimulus, isNull);
    });
  });
}
