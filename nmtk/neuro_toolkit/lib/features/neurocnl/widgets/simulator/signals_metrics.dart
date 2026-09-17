/// Pure derivations behind the Signals tab.
///
/// Kept free of Flutter so every number the tab shows can be unit-tested
/// without pumping a widget — the arithmetic here is where the mistakes live,
/// not in the painting.
library;

import 'dart:math' as math;

/// Milliseconds per timestep for a run, read from its metadata.
///
/// Every run returns `dt_ms`, but the charts have historically treated a
/// timestep as one millisecond and labelled the axis "ms" regardless — which is
/// wrong for any run that does not happen to use `dt_ms == 1.0`, and silently
/// so. Read it through here rather than assuming.
double resolveDtMs(Map<String, dynamic> metadata) {
  final raw = metadata['dt_ms'];
  if (raw is num && raw > 0) return raw.toDouble();
  return 1.0;
}

/// Total wall-clock span of a run in milliseconds.
double runDurationMs(Map<String, dynamic> metadata, int timesteps) =>
    timesteps * resolveDtMs(metadata);

/// How busy one population was over a run.
class PopulationStats {
  /// Every spike this population emitted.
  final int spikeCount;

  /// Neurons in the population, including ones that never fired.
  final int neuronCount;

  /// Neurons that fired at least once.
  final int activeNeurons;

  /// Mean firing rate across the whole population, in hertz.
  ///
  /// Averaged over *all* neurons, not just the active ones, so a population
  /// where one cell screams and forty stay silent reads as quiet — which is
  /// what it is.
  final double meanRateHz;

  const PopulationStats({
    required this.spikeCount,
    required this.neuronCount,
    required this.activeNeurons,
    required this.meanRateHz,
  });

  int get silentNeurons => math.max(0, neuronCount - activeNeurons);
}

/// Spike counts and firing rate for one population.
///
/// [neurons] maps neuron index (as a string) to the timesteps it fired at. The
/// backend omits neurons that never fired, so pass [neuronCount] whenever the
/// true population size is known — deriving it from the map would divide by the
/// count of *active* neurons and inflate the rate.
PopulationStats populationStats(
  Map<String, List<int>> neurons, {
  required int timesteps,
  required double dtMs,
  int? neuronCount,
}) {
  var spikeCount = 0;
  var activeNeurons = 0;
  for (final times in neurons.values) {
    if (times.isEmpty) continue;
    spikeCount += times.length;
    activeNeurons++;
  }

  final population = math.max(neuronCount ?? neurons.length, activeNeurons);
  final windowSeconds = timesteps * dtMs / 1000.0;
  final meanRateHz = (population <= 0 || windowSeconds <= 0)
      ? 0.0
      : spikeCount / (population * windowSeconds);

  return PopulationStats(
    spikeCount: spikeCount,
    neuronCount: population,
    activeNeurons: activeNeurons,
    meanRateHz: meanRateHz,
  );
}

/// Spike trains as dense rows, one per neuron index, in milliseconds.
///
/// Silent neurons get an empty row rather than being skipped, so a row's
/// position in the returned list *is* its neuron index. Dropping them would
/// slide every later neuron up the raster and quietly mislabel the whole plot.
List<List<double>> rasterRows(
  Map<String, List<int>> neurons, {
  required double dtMs,
  int? neuronCount,
}) {
  var highestIndex = -1;
  final byIndex = <int, List<int>>{};
  for (final entry in neurons.entries) {
    final index = int.tryParse(entry.key);
    if (index == null || index < 0) continue;
    byIndex[index] = entry.value;
    highestIndex = math.max(highestIndex, index);
  }

  final rows = math.max(neuronCount ?? 0, highestIndex + 1);
  return List<List<double>>.generate(rows, (index) {
    final times = byIndex[index];
    if (times == null || times.isEmpty) return const <double>[];
    return times.map((t) => t * dtMs).toList(growable: false);
  }, growable: false);
}
