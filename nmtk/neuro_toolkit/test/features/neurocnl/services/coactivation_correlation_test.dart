// Unit tests for the CEL-140 client-side co-activation correlation engine.
//
// These pin down the "fire together, wire together" proxy the network view
// consumes: sliding-window Pearson correlation over layer-level spike rates,
// review-mode binning of a stored PreviewPlayback, union-find clustering at
// the 0.5 threshold, and the edge-id → correlation map used for wire styling.

import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/preview.dart';
import 'package:neuro_toolkit/features/neurocnl/services/coactivation_correlation.dart';

CanvasEdge _edge(String id, String source, String target) => CanvasEdge(
  id: id,
  sourceNodeId: source,
  sourcePort: 'out',
  targetNodeId: target,
  targetPort: 'in',
  parameters: const <String, dynamic>{},
);

CanvasGraph _graph(List<CanvasEdge> edges) => CanvasGraph(
  nodes: const <CanvasNode>[],
  edges: edges,
  metadata: const <String, dynamic>{},
);

PreviewPlayback _playback({
  required double durationMs,
  required Map<String, List<double>> spikesByNode,
}) {
  return PreviewPlayback(
    durationMs: durationMs,
    nodes: <PreviewNodePlayback>[
      for (final entry in spikesByNode.entries)
        PreviewNodePlayback(
          nodeId: entry.key,
          spikeTrains: <String, List<double>>{'0': entry.value},
          spikeCount: entry.value.length,
        ),
    ],
  );
}

void main() {
  group('pearson', () {
    test('is 1 for a perfectly correlated pair', () {
      final r = pearson(
        const <double>[1, 2, 3, 4, 5, 6, 7, 8],
        const <double>[2, 4, 6, 8, 10, 12, 14, 16],
      );
      expect(r, isNotNull);
      expect(r!, closeTo(1.0, 1e-9));
    });

    test('is -1 for a perfectly anti-correlated pair', () {
      final r = pearson(
        const <double>[1, 2, 3, 4, 5, 6, 7, 8],
        const <double>[16, 14, 12, 10, 8, 6, 4, 2],
      );
      expect(r!, closeTo(-1.0, 1e-9));
    });

    test('is null for a constant series (undefined correlation)', () {
      expect(
        pearson(
          const <double>[3, 3, 3, 3, 3, 3, 3, 3],
          const <double>[1, 2, 3, 4, 5, 6, 7, 8],
        ),
        isNull,
      );
    });

    test('is null below two samples', () {
      expect(pearson(const <double>[1], const <double>[2]), isNull);
    });
  });

  group('CoactivationWindow', () {
    test('scores a pair only after enough overlapping samples', () {
      final window = CoactivationWindow(minSamples: 4);
      for (var i = 0; i < 3; i += 1) {
        window.addSample(<String, double>{
          'a': i.toDouble(),
          'b': i.toDouble(),
        });
      }
      expect(window.correlation('a', 'b'), isNull);

      window.addSample(const <String, double>{'a': 3, 'b': 3});
      expect(window.correlation('a', 'b'), closeTo(1.0, 1e-9));
    });

    test('aligns a node that appears mid-stream without inventing samples', () {
      final window = CoactivationWindow(minSamples: 2);
      window.addSample(const <String, double>{'a': 0});
      window.addSample(const <String, double>{'a': 1, 'b': 1});
      window.addSample(const <String, double>{'a': 2, 'b': 2});
      // Only the two shared ticks count; the leading null is skipped.
      expect(window.correlation('a', 'b'), closeTo(1.0, 1e-9));
    });

    test('correlationMatrix is symmetric and omits no-evidence pairs', () {
      final window = CoactivationWindow(minSamples: 3);
      for (var i = 0; i < 5; i += 1) {
        window.addSample(<String, double>{
          'a': i.toDouble(),
          'b': i.toDouble(),
          'c': (5 - i).toDouble(),
        });
      }
      final matrix = window.correlationMatrix();
      expect(matrix['a']!['b'], closeTo(matrix['b']!['a']!, 1e-9));
      expect(matrix['a']!['c'], closeTo(-1.0, 1e-9));
    });

    test('evicts the oldest sample beyond capacity', () {
      final window = CoactivationWindow(capacity: 3, minSamples: 2);
      for (var i = 0; i < 10; i += 1) {
        window.addSample(<String, double>{
          'a': i.toDouble(),
          'b': i.toDouble(),
        });
      }
      expect(window.length, 3);
      expect(window.correlation('a', 'b'), closeTo(1.0, 1e-9));
    });

    test('empty samples are ignored', () {
      final window = CoactivationWindow();
      window.addSample(const <String, double>{});
      expect(window.isEmpty, isTrue);
    });
  });

  group('CoactivationSnapshot clusters', () {
    test('groups pairs at or above the threshold and omits singletons', () {
      const snapshot = CoactivationSnapshot(
        correlations: <String, Map<String, double>>{
          'a': <String, double>{'b': 0.9, 'c': 0.1},
          'b': <String, double>{'a': 0.9},
          'c': <String, double>{'a': 0.1},
          'd': <String, double>{},
        },
      );
      final clusters = snapshot.clustersAt(0.5);
      expect(clusters, hasLength(1));
      expect(clusters.single, <String>{'a', 'b'});
    });

    test('chains transitive co-active pairs into one cluster', () {
      const snapshot = CoactivationSnapshot(
        correlations: <String, Map<String, double>>{
          'a': <String, double>{'b': 0.8},
          'b': <String, double>{'a': 0.8, 'c': 0.7},
          'c': <String, double>{'b': 0.7},
        },
      );
      expect(snapshot.clusters.single, <String>{'a', 'b', 'c'});
    });
  });

  group('coactivationEdgeStrengths', () {
    test('maps each edge to its endpoint correlation', () {
      final graph = _graph(<CanvasEdge>[
        _edge('e1', 'a', 'b'),
        _edge('e2', 'b', 'c'),
      ]);
      const snapshot = CoactivationSnapshot(
        correlations: <String, Map<String, double>>{
          'a': <String, double>{'b': 0.75},
          'b': <String, double>{'a': 0.75},
        },
      );
      final strengths = coactivationEdgeStrengths(graph, snapshot);
      expect(strengths['e1'], closeTo(0.75, 1e-9));
      // No evidence for b–c: omitted, not zero.
      expect(strengths.containsKey('e2'), isFalse);
    });

    test('returns empty when the snapshot is null or empty', () {
      final graph = _graph(<CanvasEdge>[_edge('e1', 'a', 'b')]);
      expect(coactivationEdgeStrengths(graph, null), isEmpty);
      expect(
        coactivationEdgeStrengths(graph, const CoactivationSnapshot()),
        isEmpty,
      );
    });
  });

  group('PlaybackRateSeries', () {
    test('bins spikes into fixed windows and normalizes to the peak', () {
      final playback = _playback(
        durationMs: 200,
        spikesByNode: <String, List<double>>{
          'a': <double>[0, 10, 20, 30],
          'b': <double>[100],
        },
      );
      final series = PlaybackRateSeries.fromPlayback(playback, binMs: 50);
      expect(series.binCount, 4);
      // Bin 0 holds 4 spikes for 'a', the global peak → normalized 1.0.
      expect(series.rateAt('a', 0), closeTo(1.0, 1e-9));
      // 'a' is quiet in bin 2.
      expect(series.rateAt('a', 2), closeTo(0.0, 1e-9));
      // 'b' has a single spike in bin 2 → 1/4.
      expect(series.rateAt('b', 2), closeTo(0.25, 1e-9));
    });

    test('ratesAtTime selects the bin containing the timestamp', () {
      final playback = _playback(
        durationMs: 200,
        spikesByNode: <String, List<double>>{
          'a': <double>[0, 10, 20, 30, 100],
        },
      );
      final series = PlaybackRateSeries.fromPlayback(playback, binMs: 50);
      // Bin 0 peak of 4 spikes → 1.0; bin 2 holds one spike → 0.25.
      expect(series.ratesAtTime(0)['a'], closeTo(1.0, 1e-9));
      expect(series.ratesAtTime(120)['a'], closeTo(0.25, 1e-9));
    });

    test('empty playback yields no bins', () {
      final series = PlaybackRateSeries.fromPlayback(
        const PreviewPlayback(durationMs: 0),
      );
      expect(series.isEmpty, isTrue);
      expect(series.ratesAtTime(0), isEmpty);
    });
  });

  group('CoactivationSnapshot.fromPlayback', () {
    test('correlates nodes that spike together in the same bins', () {
      final playback = _playback(
        durationMs: 500,
        spikesByNode: <String, List<double>>{
          // 'a' and 'b' both fire once in bins 0-4 and stay quiet in bins
          // 5-9. Identical non-constant series → correlation 1.0.
          'a': <double>[0, 50, 100, 150, 200],
          'b': <double>[0, 50, 100, 150, 200],
        },
      );
      final snapshot = CoactivationSnapshot.fromPlayback(playback, binMs: 50);
      expect(snapshot.correlation('a', 'b'), isNotNull);
      expect(snapshot.correlation('a', 'b')!, closeTo(1.0, 1e-9));
    });
  });
}
