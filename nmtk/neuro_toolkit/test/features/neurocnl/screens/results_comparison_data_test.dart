import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_comparison_data.dart';

void main() {
  group('computePlatformSummaries', () {
    test('returns empty list for empty history', () {
      expect(computePlatformSummaries({}), isEmpty);
    });

    test('single platform — computes bestAccuracy, bestLoss, finalLoss', () {
      final history = {
        'snntorch_sim': [
          const TrainingEpochEvent(
            epoch: 1,
            loss: 0.9,
            accuracy: 0.60,
            totalEpochs: 3,
          ),
          const TrainingEpochEvent(
            epoch: 2,
            loss: 0.5,
            accuracy: 0.75,
            totalEpochs: 3,
          ),
          const TrainingEpochEvent(
            epoch: 3,
            loss: 0.7,
            accuracy: 0.70,
            totalEpochs: 3,
          ),
        ],
      };
      final summaries = computePlatformSummaries(history);
      expect(summaries.length, 1);
      final s = summaries.first;
      expect(s.platformId, 'snntorch_sim');
      expect(s.epochs, 3);
      expect(s.bestAccuracy, closeTo(0.75, 0.001));
      expect(s.bestLoss, closeTo(0.5, 0.001));
      expect(s.finalLoss, closeTo(0.7, 0.001));
    });

    test(
      'multi-platform — returns one summary per platform in insertion order',
      () {
        final history = {
          'snntorch_sim': [
            const TrainingEpochEvent(
              epoch: 1,
              loss: 0.5,
              accuracy: 0.8,
              totalEpochs: 2,
            ),
            const TrainingEpochEvent(
              epoch: 2,
              loss: 0.3,
              accuracy: 0.9,
              totalEpochs: 2,
            ),
          ],
          'lava_sim': [
            const TrainingEpochEvent(
              epoch: 1,
              loss: 0.7,
              accuracy: 0.65,
              totalEpochs: 2,
            ),
            const TrainingEpochEvent(
              epoch: 2,
              loss: 0.4,
              accuracy: 0.72,
              totalEpochs: 2,
            ),
          ],
        };
        final summaries = computePlatformSummaries(history);
        expect(summaries.length, 2);
        expect(summaries[0].platformId, 'snntorch_sim');
        expect(summaries[1].platformId, 'lava_sim');
      },
    );

    test('bestAccuracy is null when no accuracy in events', () {
      final history = {
        'snntorch_sim': [
          const TrainingEpochEvent(epoch: 1, loss: 0.8, totalEpochs: 1),
        ],
      };
      final summaries = computePlatformSummaries(history);
      expect(summaries.first.bestAccuracy, isNull);
      expect(summaries.first.accuracyCurve, isEmpty);
    });

    test('lossCurve has (epochNumber, loss) per epoch, 1-indexed', () {
      final history = {
        'p1': [
          const TrainingEpochEvent(epoch: 1, loss: 0.9, totalEpochs: 3),
          const TrainingEpochEvent(epoch: 2, loss: 0.6, totalEpochs: 3),
          const TrainingEpochEvent(epoch: 3, loss: 0.3, totalEpochs: 3),
        ],
      };
      final curve = computePlatformSummaries(history).first.lossCurve;
      expect(curve.length, 3);
      expect(curve[0], (1, 0.9));
      expect(curve[2], (3, 0.3));
    });

    test('accuracyCurve skips null-accuracy epochs', () {
      final history = {
        'p1': [
          const TrainingEpochEvent(epoch: 1, loss: 0.9, totalEpochs: 3),
          const TrainingEpochEvent(
            epoch: 2,
            loss: 0.6,
            accuracy: 0.5,
            totalEpochs: 3,
          ),
          const TrainingEpochEvent(epoch: 3, loss: 0.3, totalEpochs: 3),
        ],
      };
      final curve = computePlatformSummaries(history).first.accuracyCurve;
      expect(curve.length, 1);
      expect(curve[0], (2, 0.5));
    });

    test('empty epoch list — bestLoss and finalLoss are double.infinity', () {
      final history = {'p1': <TrainingEpochEvent>[]};
      final s = computePlatformSummaries(history).first;
      expect(s.bestLoss, double.infinity);
      expect(s.finalLoss, double.infinity);
      expect(s.epochs, 0);
    });
  });
}
