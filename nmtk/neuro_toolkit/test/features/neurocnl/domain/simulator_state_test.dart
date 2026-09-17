import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/simulator_provider.dart';

void main() {
  group('formatSimulatorRunError', () {
    test('joins status code, message, and extra details', () {
      const error = SimulatorRunError(
        'Simulation backend rejected the NIR.',
        details: ['Population "hidden" exceeds neuron limit.'],
        statusCode: 422,
      );

      expect(
        formatSimulatorRunError(error),
        'HTTP 422\n'
        'Simulation backend rejected the NIR.\n'
        'Population "hidden" exceeds neuron limit.',
      );
    });

    test('omits duplicate detail lines that repeat the message', () {
      const error = SimulatorRunError(
        'Run failed.',
        details: ['Run failed.', 'Check timesteps.'],
      );

      expect(formatSimulatorRunError(error), 'Run failed.\nCheck timesteps.');
    });
  });
}
