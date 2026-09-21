import 'dart:math' as math;

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/preview.dart';

/// Pearson correlation at or above which two layers are treated as a
/// "fire together, wire together" cluster.
const double kCoactivationClusterThreshold = 0.5;

/// Minimum number of overlapping samples before a pair is scored. Below this
/// the correlation is statistically meaningless and is reported as `null`.
const int kCoactivationMinSamples = 8;

/// Default number of trailing samples retained by [CoactivationWindow].
const int kCoactivationDefaultWindowCapacity = 120;

/// Default time bin used when deriving per-layer rate series from a stored
/// [PreviewPlayback].
const double kCoactivationDefaultBinMs = 50.0;

/// Minimum number of overlapping samples before a co-firing score is reported.
/// Deliberately lower than [kCoactivationMinSamples]: a run with only a few
/// captured epochs should still show which nodes fired together.
const int kCoactivationMinCofiringSamples = 3;

/// A node counts as "active" in a sample when its normalized rate reaches this
/// value. Used only by the co-firing score, not by the Pearson correlation.
const double kCoactivationActiveThreshold = 0.25;

/// Short label for the correlation overlay.
const String kCoactivationShortLabel = 'Co-active';

/// Mandated UI copy: the correlation is a coarse layer-level proxy for
/// Hebbian co-activation, not a per-neuron measurement.
const String kCoactivationProxyDisclosure =
    'Wire brightness reflects co-activation (a layer-level proxy for Hebbian '
    'correlation, not per-neuron).';

/// Sliding-window Pearson correlation over layer-level spike-rate samples.
///
/// Each [addSample] call is one tick: a map from canvas node id to a
/// normalized spike rate in `0..1`. Samples are aligned by insertion order, so
/// a node that first appears mid-stream keeps `null` for the ticks it was
/// absent and is simply skipped when scoring a pair. This mirrors the
/// "fire together, wire together" proxy from CEL-138/140: it is a coarse
/// layer-level signal, deliberately not a per-neuron spike-train correlation.
class CoactivationWindow {
  CoactivationWindow({
    this.capacity = kCoactivationDefaultWindowCapacity,
    this.minSamples = kCoactivationMinSamples,
  }) : assert(capacity > 1),
       assert(minSamples >= 2);

  /// Maximum number of trailing samples retained.
  final int capacity;

  /// Minimum overlapping samples required before a pair is scored.
  final int minSamples;

  final List<Map<String, double>> _samples = <Map<String, double>>[];
  final Map<String, List<double?>> _series = <String, List<double?>>{};

  /// Number of samples currently retained.
  int get length => _samples.length;

  bool get isEmpty => _samples.isEmpty;

  /// Node ids seen at least once in the retained window.
  Iterable<String> get nodeIds => _series.keys;

  /// Appends one tick of per-node rates. Empty maps are ignored so a quiet
  /// tick does not pad every series with nulls.
  void addSample(Map<String, double> rates) {
    if (rates.isEmpty) return;

    _samples.add(Map<String, double>.from(rates));

    for (final entry in _series.entries) {
      entry.value.add(rates[entry.key]);
    }

    for (final entry in rates.entries) {
      if (_series.containsKey(entry.key)) continue;
      final series = List<double?>.filled(
        _samples.length - 1,
        null,
        growable: true,
      )..add(entry.value);
      _series[entry.key] = series;
    }

    if (_samples.length > capacity) {
      _samples.removeAt(0);
      for (final series in _series.values) {
        if (series.isNotEmpty) series.removeAt(0);
      }
    }
  }

  void clear() {
    _samples.clear();
    _series.clear();
  }

  /// Pearson correlation of [a] and [b] over their overlapping samples, or
  /// `null` when there is too little evidence or either series is constant.
  double? correlation(String a, String b) {
    if (a == b) return 1.0;
    final seriesA = _series[a];
    final seriesB = _series[b];
    if (seriesA == null || seriesB == null) return null;

    final length = math.min(seriesA.length, seriesB.length);
    final xs = <double>[];
    final ys = <double>[];
    for (var i = 0; i < length; i += 1) {
      final x = seriesA[i];
      final y = seriesB[i];
      if (x == null || y == null) continue;
      xs.add(x);
      ys.add(y);
    }
    if (xs.length < minSamples) return null;
    return pearson(xs, ys);
  }

  /// Symmetric correlation map: `matrix[a][b] == matrix[b][a]`. Pairs without
  /// enough evidence are omitted (no evidence, not zero).
  Map<String, Map<String, double>> correlationMatrix() {
    final ids = _series.keys.toList(growable: false);
    final result = <String, Map<String, double>>{};
    for (var i = 0; i < ids.length; i += 1) {
      for (var j = i + 1; j < ids.length; j += 1) {
        final r = correlation(ids[i], ids[j]);
        if (r == null) continue;
        (result[ids[i]] ??= <String, double>{})[ids[j]] = r;
        (result[ids[j]] ??= <String, double>{})[ids[i]] = r;
      }
    }
    return result;
  }

  /// Jaccard co-firing score for a pair: of the samples where *either* node is
  /// active (rate ≥ [activeThreshold]), the fraction where *both* are. Returns
  /// `null` below the required overlap or when neither node ever fires.
  ///
  /// This is the direct "fire together" signal. Pearson washes out to ~0 for
  /// two sparse spike trains even when they reliably fire in the same bins;
  /// Jaccard does not, so co-active nodes actually get a wire.
  double? cofiring(
    String a,
    String b, {
    double activeThreshold = kCoactivationActiveThreshold,
    int? minSamples,
  }) {
    if (a == b) return 1.0;
    final seriesA = _series[a];
    final seriesB = _series[b];
    if (seriesA == null || seriesB == null) return null;

    final required =
        minSamples ??
        math.min(this.minSamples, kCoactivationMinCofiringSamples);
    final length = math.min(seriesA.length, seriesB.length);
    var both = 0;
    var either = 0;
    var overlap = 0;
    for (var i = 0; i < length; i += 1) {
      final x = seriesA[i];
      final y = seriesB[i];
      if (x == null || y == null) continue;
      overlap += 1;
      final xActive = x >= activeThreshold;
      final yActive = y >= activeThreshold;
      if (xActive || yActive) either += 1;
      if (xActive && yActive) both += 1;
    }
    if (overlap < required || either == 0) return null;
    return both / either;
  }

  /// Symmetric co-firing matrix in the same shape as [correlationMatrix].
  Map<String, Map<String, double>> cofiringMatrix({
    double activeThreshold = kCoactivationActiveThreshold,
  }) {
    final ids = _series.keys.toList(growable: false);
    final result = <String, Map<String, double>>{};
    for (var i = 0; i < ids.length; i += 1) {
      for (var j = i + 1; j < ids.length; j += 1) {
        final score = cofiring(
          ids[i],
          ids[j],
          activeThreshold: activeThreshold,
        );
        if (score == null || score <= 0) continue;
        (result[ids[i]] ??= <String, double>{})[ids[j]] = score;
        (result[ids[j]] ??= <String, double>{})[ids[i]] = score;
      }
    }
    return result;
  }
}

/// Immutable correlation result used by the renderer.
class CoactivationSnapshot {
  const CoactivationSnapshot({
    this.correlations = const <String, Map<String, double>>{},
    this.cofiring = const <String, Map<String, double>>{},
    this.threshold = kCoactivationClusterThreshold,
  });

  /// Symmetric node-id → node-id → Pearson `r`.
  final Map<String, Map<String, double>> correlations;

  /// Symmetric node-id → node-id → Jaccard co-firing score in `0..1`. This is
  /// the direct "fire together" signal the renderer draws wires from; it is
  /// empty for snapshots built without a [CoactivationWindow].
  final Map<String, Map<String, double>> cofiring;

  /// Threshold used to derive [clusters].
  final double threshold;

  bool get isEmpty => correlations.isEmpty && cofiring.isEmpty;

  /// Correlation for a pair, or `null` when there is no evidence. A node
  /// correlated with itself is `1.0`.
  double? correlation(String a, String b) {
    if (a == b) return 1.0;
    return correlations[a]?[b] ?? correlations[b]?[a];
  }

  /// Wire strength for a pair: the stronger of `|Pearson r|` and the Jaccard
  /// co-firing score. Merged so a pair that reliably fires together still gets
  /// a wire when Pearson is too weak to register. Symmetric; `0` when there is
  /// no evidence.
  double coactivation(String a, String b) {
    if (a == b) return 1.0;
    final r = correlations[a]?[b] ?? correlations[b]?[a];
    final c = cofiring[a]?[b] ?? cofiring[b]?[a];
    final magnitude = r == null ? 0.0 : r.abs();
    return math.max(magnitude, c ?? 0.0);
  }

  /// Symmetric merged wire matrix: per pair, the stronger of `|Pearson r|` and
  /// the co-firing score. Returns [correlations] unchanged when there is no
  /// co-firing evidence.
  Map<String, Map<String, double>> coactivationMatrix() {
    if (cofiring.isEmpty) return correlations;
    final result = <String, Map<String, double>>{};
    void merge(String a, String b, double value) {
      if (value <= 0 || a == b) return;
      final rowA = result[a] ??= <String, double>{};
      final rowB = result[b] ??= <String, double>{};
      final existing = rowA[b] ?? rowB[a] ?? 0.0;
      if (value <= existing) return;
      rowA[b] = value;
      rowB[a] = value;
    }

    correlations.forEach((a, row) {
      row.forEach((b, r) => merge(a, b, r.abs()));
    });
    cofiring.forEach((a, row) {
      row.forEach((b, c) => merge(a, b, c));
    });
    return result;
  }

  factory CoactivationSnapshot.fromWindow(
    CoactivationWindow window, {
    double threshold = kCoactivationClusterThreshold,
  }) {
    return CoactivationSnapshot(
      correlations: window.correlationMatrix(),
      cofiring: window.cofiringMatrix(),
      threshold: threshold,
    );
  }

  factory CoactivationSnapshot.fromRateSeries(
    PlaybackRateSeries series, {
    double threshold = kCoactivationClusterThreshold,
  }) {
    final window = CoactivationWindow();
    final ids = series.nodeIds.toList(growable: false);
    for (var bin = 0; bin < series.binCount; bin += 1) {
      window.addSample(<String, double>{
        for (final id in ids) id: series.rateAt(id, bin),
      });
    }
    return CoactivationSnapshot.fromWindow(window, threshold: threshold);
  }

  factory CoactivationSnapshot.fromPlayback(
    PreviewPlayback playback, {
    double threshold = kCoactivationClusterThreshold,
    double binMs = kCoactivationDefaultBinMs,
  }) {
    return CoactivationSnapshot.fromRateSeries(
      PlaybackRateSeries.fromPlayback(playback, binMs: binMs),
      threshold: threshold,
    );
  }

  /// Union-find clusters over pairs whose merged co-activation strength
  /// (`max(|Pearson r|, co-firing)`) is at least [threshold]. Singletons are
  /// omitted.
  List<Set<String>> clustersAt(double threshold) {
    final matrix = coactivationMatrix();
    final ids = <String>{...matrix.keys};
    for (final inner in matrix.values) {
      ids.addAll(inner.keys);
    }
    if (ids.isEmpty) return const <Set<String>>[];

    final parent = <String, String>{for (final id in ids) id: id};
    String find(String value) {
      var current = value;
      while (parent[current] != current) {
        parent[current] = parent[parent[current]!]!;
        current = parent[current]!;
      }
      return current;
    }

    void union(String a, String b) {
      final rootA = find(a);
      final rootB = find(b);
      if (rootA != rootB) parent[rootA] = rootB;
    }

    for (final entry in matrix.entries) {
      for (final other in entry.value.entries) {
        if (entry.key.compareTo(other.key) >= 0) continue;
        if (other.value >= threshold) union(entry.key, other.key);
      }
    }

    final groups = <String, Set<String>>{};
    for (final id in ids) {
      (groups[find(id)] ??= <String>{}).add(id);
    }
    return groups.values
        .where((group) => group.length > 1)
        .toList(growable: false);
  }

  List<Set<String>> get clusters => clustersAt(threshold);
}

/// Per-node spike-rate series binned from a stored [PreviewPlayback], used for
/// post-run review mode. Rates are normalized by the global peak bin so the
/// values stay in `0..1`, matching the live `training_mode_provider` rates the
/// renderer already consumes.
class PlaybackRateSeries {
  const PlaybackRateSeries({
    required this.binMs,
    required this.binCount,
    required this.ratesByNode,
  });

  final double binMs;
  final int binCount;
  final Map<String, List<double>> ratesByNode;

  bool get isEmpty => ratesByNode.isEmpty || binCount == 0;

  Iterable<String> get nodeIds => ratesByNode.keys;

  factory PlaybackRateSeries.fromPlayback(
    PreviewPlayback playback, {
    double binMs = kCoactivationDefaultBinMs,
  }) {
    final effectiveBin = binMs > 0 ? binMs : kCoactivationDefaultBinMs;
    final binCount = playback.durationMs <= 0
        ? 0
        : (playback.durationMs / effectiveBin).ceil();

    final counts = <String, List<double>>{};
    List<double> seriesFor(String id) =>
        counts.putIfAbsent(id, () => List<double>.filled(binCount, 0.0));

    void addSpike(String nodeId, double timeMs) {
      if (binCount == 0) return;
      final index = (timeMs / effectiveBin).floor().clamp(0, binCount - 1);
      seriesFor(nodeId)[index] += 1.0;
    }

    for (final node in playback.nodes) {
      seriesFor(node.nodeId);
      for (final train in node.spikeTrains.values) {
        for (final timeMs in train) {
          addSpike(node.nodeId, timeMs);
        }
      }
    }

    // Legacy payloads may only carry flat spike events.
    if (counts.values.every((series) => series.every((v) => v == 0)) &&
        playback.spikeEvents.isNotEmpty) {
      for (final event in playback.spikeEvents) {
        addSpike(event.nodeId, event.timeMs);
      }
    }

    var peak = 0.0;
    for (final series in counts.values) {
      for (final value in series) {
        if (value > peak) peak = value;
      }
    }

    final rates = <String, List<double>>{
      for (final entry in counts.entries)
        entry.key: peak <= 0
            ? List<double>.filled(binCount, 0.0)
            : <double>[for (final value in entry.value) value / peak],
    };

    return PlaybackRateSeries(
      binMs: effectiveBin,
      binCount: binCount,
      ratesByNode: rates,
    );
  }

  double rateAt(String nodeId, int bin) {
    final series = ratesByNode[nodeId];
    if (series == null || series.isEmpty) return 0.0;
    return series[bin.clamp(0, series.length - 1)];
  }

  /// Per-node rate for the bin that contains [timeMs]. Empty when the
  /// playback has no duration.
  Map<String, double> ratesAtTime(double timeMs) {
    if (binCount == 0) return const <String, double>{};
    final bin = (timeMs / binMs).floor().clamp(0, binCount - 1);
    return <String, double>{
      for (final id in ratesByNode.keys) id: ratesByNode[id]![bin],
    };
  }
}

/// Maps every graph edge to its endpoints' correlation. Edges with no
/// evidence are omitted entirely — a missing entry means "no evidence", not
/// zero.
Map<String, double> coactivationEdgeStrengths(
  CanvasGraph graph,
  CoactivationSnapshot? snapshot,
) {
  if (snapshot == null || snapshot.isEmpty) return const <String, double>{};
  final result = <String, double>{};
  for (final edge in graph.edges) {
    final r = snapshot.correlation(edge.sourceNodeId, edge.targetNodeId);
    if (r != null) result[edge.id] = r;
  }
  return result;
}

/// Undirected correlation pairs above [min], for brainviz edge rendering.
List<({String a, String b, double strength})> correlationPairs(
  Map<String, Map<String, double>> matrix, {
  double min = 0.05,
}) {
  if (matrix.isEmpty) return const [];
  final pairs = <({String a, String b, double strength})>[];
  final ids = matrix.keys.toList()..sort();
  for (var i = 0; i < ids.length; i++) {
    final a = ids[i];
    final row = matrix[a];
    if (row == null) continue;
    for (var j = i + 1; j < ids.length; j++) {
      final b = ids[j];
      final r = row[b] ?? matrix[b]?[a];
      if (r == null || r <= min) continue;
      pairs.add((a: a, b: b, strength: r.clamp(0.0, 1.0)));
    }
  }
  return pairs;
}

/// Count of correlation partners at or above [min] per node id.
Map<String, int> correlationDegrees(
  Map<String, Map<String, double>> matrix, {
  double min = 0.05,
}) {
  final degrees = <String, int>{};
  for (final pair in correlationPairs(matrix, min: min)) {
    degrees.update(pair.a, (value) => value + 1, ifAbsent: () => 1);
    degrees.update(pair.b, (value) => value + 1, ifAbsent: () => 1);
  }
  return degrees;
}

/// Stable cluster index per node id (`0`-based). Singletons are omitted.
Map<String, int> coactivationClusterIndices(CoactivationSnapshot? snapshot) {
  if (snapshot == null || snapshot.isEmpty) return const <String, int>{};
  final indices = <String, int>{};
  var clusterIndex = 0;
  for (final cluster in snapshot.clusters) {
    for (final nodeId in cluster) {
      indices[nodeId] = clusterIndex;
    }
    clusterIndex++;
  }
  return indices;
}

/// Pearson correlation coefficient of two equal-length samples. Returns
/// `null` when either input is constant (undefined correlation) or too short.
double? pearson(List<double> xs, List<double> ys) {
  final n = math.min(xs.length, ys.length);
  if (n < 2) return null;

  var sumX = 0.0;
  var sumY = 0.0;
  var sumXX = 0.0;
  var sumYY = 0.0;
  var sumXY = 0.0;
  for (var i = 0; i < n; i += 1) {
    final x = xs[i];
    final y = ys[i];
    sumX += x;
    sumY += y;
    sumXX += x * x;
    sumYY += y * y;
    sumXY += x * y;
  }

  final covariance = sumXY - (sumX * sumY) / n;
  final varianceX = sumXX - (sumX * sumX) / n;
  final varianceY = sumYY - (sumY * sumY) / n;
  if (varianceX <= 1e-9 || varianceY <= 1e-9) return null;

  final r = covariance / math.sqrt(varianceX * varianceY);
  if (r.isNaN) return null;
  return r.clamp(-1.0, 1.0);
}
