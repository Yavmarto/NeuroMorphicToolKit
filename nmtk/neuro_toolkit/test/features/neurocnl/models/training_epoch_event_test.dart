import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_provider.dart';

void main() {
  group('TrainingEpochEvent.fromJson', () {
    test('parses accuracy and layerSpikeRates fields', () {
      final event = TrainingEpochEvent.fromJson({
        'epoch': 5,
        'total_epochs': 100,
        'loss': 0.42,
        'accuracy': 0.87,
        'layer_spike_rates': {'layer_0': 0.12, 'layer_1': 0.08},
        'platform': 'snntorch_sim',
      });
      expect(event.epoch, equals(5));
      expect(event.accuracy, closeTo(0.87, 0.001));
      expect(event.layerSpikeRates, equals({'layer_0': 0.12, 'layer_1': 0.08}));
      expect(event.platform, equals('snntorch_sim'));
    });

    test('handles missing optional fields gracefully', () {
      final event = TrainingEpochEvent.fromJson({'epoch': 1, 'loss': 0.9});
      expect(event.accuracy, isNull);
      expect(event.layerSpikeRates, isEmpty);
      expect(event.platform, isNull);
    });
  });
}
