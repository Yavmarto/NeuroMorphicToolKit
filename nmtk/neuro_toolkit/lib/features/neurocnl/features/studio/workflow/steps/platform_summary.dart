import 'package:flutter/foundation.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/training_provider.dart';

class PlatformSummary {
  const PlatformSummary({
    required this.platformId,
    required this.epochs,
    required this.bestAccuracy,
    required this.bestLoss,
    required this.finalLoss,
    required this.lossCurve,
    required this.accuracyCurve,
  });

  final String platformId;
  final int epochs;
  final double? bestAccuracy;
  final double bestLoss;
  final double finalLoss;
  final List<(int, double)> lossCurve;
  final List<(int, double)> accuracyCurve;

  @override
  bool operator ==(Object other) =>
      other is PlatformSummary &&
      other.platformId == platformId &&
      other.epochs == epochs &&
      other.bestAccuracy == bestAccuracy &&
      other.bestLoss == bestLoss &&
      other.finalLoss == finalLoss &&
      listEquals(other.lossCurve, lossCurve) &&
      listEquals(other.accuracyCurve, accuracyCurve);

  @override
  int get hashCode => Object.hash(
    platformId,
    epochs,
    bestAccuracy,
    bestLoss,
    finalLoss,
    Object.hashAll(lossCurve),
    Object.hashAll(accuracyCurve),
  );
}

List<PlatformSummary> computePlatformSummaries(
  Map<String, List<TrainingEpochEvent>> history,
) => history.entries.map((entry) {
  final epochs = entry.value;
  double? bestAccuracy;
  double? bestLoss;
  for (final epoch in epochs) {
    if (epoch.accuracy != null &&
        (bestAccuracy == null || epoch.accuracy! > bestAccuracy)) {
      bestAccuracy = epoch.accuracy;
    }
    if (bestLoss == null || epoch.loss < bestLoss) {
      bestLoss = epoch.loss;
    }
  }
  return PlatformSummary(
    platformId: entry.key,
    epochs: epochs.length,
    bestAccuracy: bestAccuracy,
    bestLoss: bestLoss ?? double.infinity,
    finalLoss: epochs.isEmpty ? double.infinity : epochs.last.loss,
    lossCurve: epochs
        .asMap()
        .entries
        .map((item) => (item.key + 1, item.value.loss))
        .toList(),
    accuracyCurve: epochs
        .asMap()
        .entries
        .where((item) => item.value.accuracy != null)
        .map((item) => (item.key + 1, item.value.accuracy!))
        .toList(),
  );
}).toList();
