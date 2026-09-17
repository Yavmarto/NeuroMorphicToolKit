import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_comparison_data.dart';

void main() {
  group('computePlatformSummaries — edge cases', () {
    test('single epoch — finalLoss equals bestLoss', () {
      final history = {
        'p1': [const TrainingEpochEvent(epoch: 1, loss: 0.42, totalEpochs: 1)],
      };
      final s = computePlatformSummaries(history).first;
      expect(s.finalLoss, closeTo(s.bestLoss, 0.0001));
    });

    test('empty epoch list — bestLoss and finalLoss are double.infinity', () {
      final history = {'empty': <TrainingEpochEvent>[]};
      final s = computePlatformSummaries(history).first;
      expect(s.bestLoss, double.infinity);
      expect(s.finalLoss, double.infinity);
      expect(s.epochs, 0);
      expect(s.bestAccuracy, isNull);
    });
  });
}
