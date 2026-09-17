// Unit tests for the spherical globe layout engine — the pure-Dart port of the
// AIS-OS `composeGlobe` placement. These pin down the deterministic,
// equal-area, per-category-sector behaviour the network view relies on:
// nodes grouped and colored by layer type, placed on a round sphere, with the
// golden-angle azimuth sequence and the orbit-radius jitter.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/globe_layout.dart';

CanvasNode _node(String id, {String? category}) {
  return CanvasNode(
    id: id,
    componentId: 'lif_population',
    nirType: 'nir.Population',
    label: id,
    parameters: const <String, dynamic>{},
    position: const <double>[0, 0],
    metadata: category == null
        ? const <String, dynamic>{}
        : <String, dynamic>{'category': category},
  );
}

CanvasGraph _graph(List<CanvasNode> nodes) {
  return CanvasGraph(
    nodes: nodes,
    edges: const <CanvasEdge>[],
    metadata: const <String, dynamic>{},
  );
}

CanvasGraph _singleCategory(int count) {
  return _graph([
    for (var i = 0; i < count; i++) _node('n${i.toString().padLeft(2, '0')}'),
  ]);
}

/// Azimuth of a point on the globe, measured from +z toward +x, in `[0, 2π)`.
double _azimuth(GlobePoint p) {
  final angle = math.atan2(p.x, p.z);
  return angle < 0 ? angle + 2 * math.pi : angle;
}

void main() {
  group('GlobeLayout placement', () {
    test('is deterministic: same graph yields identical positions', () {
      final graph = _singleCategory(9);
      final a = GlobeLayout(graph);
      final b = GlobeLayout(graph);
      expect(a.positions.keys, b.positions.keys);
      for (final id in graph.nodes.map((node) => node.id)) {
        expect(a.positions[id], b.positions[id], reason: '$id diverged');
      }
    });

    test('is independent of node insertion order within a category', () {
      final forward = _graph([_node('a'), _node('b'), _node('c')]);
      final shuffled = _graph([_node('c'), _node('a'), _node('b')]);
      final a = GlobeLayout(forward);
      final b = GlobeLayout(shuffled);
      for (final id in const ['a', 'b', 'c']) {
        expect(a.positions[id], b.positions[id]);
      }
    });

    test('every node sits exactly on its own orbit sphere', () {
      final layout = GlobeLayout(_singleCategory(12));
      for (final placement in layout.placements.values) {
        expect(
          placement.position.distance,
          closeTo(placement.radius, 1e-9),
          reason: '${placement.id} left its sphere',
        );
      }
    });

    test('orbit radii stay within the configured shell band', () {
      const config = GlobeLayoutConfig();
      final layout = GlobeLayout(_singleCategory(20));
      for (final placement in layout.placements.values) {
        expect(placement.radius, greaterThanOrEqualTo(config.baseRadius));
        expect(
          placement.radius,
          lessThan(config.baseRadius + config.radiusJitter),
        );
      }
    });

    test(
      'latitude bands are equal-area and match the composeGlobe formula',
      () {
        final layout = GlobeLayout(_singleCategory(8));
        final ids = layout.positions.keys.toList()..sort();
        final count = ids.length;
        for (var i = 0; i < count; i++) {
          final placement = layout.placements[ids[i]]!;
          final expectedLatitude = 1 - 2 * ((i + 0.5) / count);
          expect(
            placement.position.y / placement.radius,
            closeTo(expectedLatitude, 1e-9),
            reason: '${ids[i]} is not on its equal-area band',
          );
        }
      },
    );

    test('azimuths advance by the golden turn within a category', () {
      const config = GlobeLayoutConfig();
      final layout = GlobeLayout(_singleCategory(10));
      final ids = layout.positions.keys.toList()..sort();
      for (var i = 0; i < ids.length; i++) {
        final placement = layout.placements[ids[i]]!;
        final turn = (i * config.goldenTurn) % 1;
        final expectedAzimuth =
            (config.sectorInset + turn * config.sectorFill) * 2 * math.pi;
        expect(
          _azimuth(placement.position),
          closeTo(expectedAzimuth, 1e-9),
          reason: '${ids[i]} is off the golden-angle sequence',
        );
      }
    });

    test('empty graph is a no-op', () {
      final layout = GlobeLayout(_graph(const <CanvasNode>[]));
      expect(layout.placements, isEmpty);
      expect(layout.positions, isEmpty);
      expect(layout.sectors, isEmpty);
      expect(layout.boundingRadius, 0);
      expect(layout.scaledToRadius(100), isEmpty);
    });
  });

  group('GlobeLayout category grouping', () {
    CanvasGraph threeCategories() {
      return _graph([
        _node('in', category: 'io'),
        _node('h1', category: 'neuron'),
        _node('h2', category: 'neuron'),
        _node('out', category: 'io'),
        _node('loss', category: 'loss'),
      ]);
    }

    test('sectors are the distinct categories, sorted deterministically', () {
      final layout = GlobeLayout(threeCategories());
      expect(layout.sectors, const ['io', 'loss', 'neuron']);
    });

    test('each node reports its own category and sector index', () {
      final layout = GlobeLayout(threeCategories());
      expect(layout.categoryOfNode('in'), 'io');
      expect(layout.categoryOfNode('h1'), 'neuron');
      expect(layout.categoryOfNode('loss'), 'loss');
      expect(layout.sectorOf('in'), layout.sectors.indexOf('io'));
      expect(layout.sectorOf('h1'), layout.sectors.indexOf('neuron'));
      expect(layout.sectorOf('missing'), -1);
    });

    test('categories occupy disjoint azimuth sectors', () {
      final layout = GlobeLayout(threeCategories());
      final bySector = <int, List<double>>{};
      for (final placement in layout.placements.values) {
        bySector
            .putIfAbsent(placement.sector, () => <double>[])
            .add(_azimuth(placement.position));
      }
      final sectorIds = bySector.keys.toList()..sort();
      for (var i = 1; i < sectorIds.length; i++) {
        final previousMax = bySector[sectorIds[i - 1]]!.reduce(math.max);
        final currentMin = bySector[sectorIds[i]]!.reduce(math.min);
        expect(
          previousMax,
          lessThan(currentMin),
          reason: 'sector ${sectorIds[i - 1]} overlaps ${sectorIds[i]}',
        );
      }
    });

    test('a custom resolver overrides the default category source', () {
      final graph = _graph([_node('a'), _node('b')]);
      final layout = GlobeLayout(
        graph,
        categoryOf: (node) => node.id == 'a' ? 'alpha' : 'beta',
      );
      expect(layout.sectors, const ['alpha', 'beta']);
      expect(layout.categoryOfNode('a'), 'alpha');
      expect(layout.categoryOfNode('b'), 'beta');
    });

    test('sectorOrder fixes sector slots; unknown categories are appended', () {
      final layout = GlobeLayout(
        threeCategories(),
        sectorOrder: const ['neuron', 'io'],
      );
      // 'neuron' and 'io' keep their slots; 'loss' is appended sorted.
      expect(layout.sectors, const ['neuron', 'io', 'loss']);
      expect(layout.sectorOf('h1'), 0);
      expect(layout.sectorOf('in'), 1);
      expect(layout.sectorOf('loss'), 2);
      // Categories absent from the graph are silently skipped.
      final missing = GlobeLayout(
        threeCategories(),
        sectorOrder: const ['missing', 'io'],
      );
      expect(missing.sectors, const ['io', 'loss', 'neuron']);
    });

    test('an empty resolved category falls back to the config fallback', () {
      final layout = GlobeLayout(_graph([_node('a')]), categoryOf: (_) => '');
      expect(layout.sectors, const ['other']);
      expect(layout.categoryOfNode('a'), 'other');
    });

    test(
      'default resolver prefers metadata, then nirType, then componentId',
      () {
        final withMetadata = _node('m', category: 'io');
        expect(GlobeLayout.defaultCategoryOf(withMetadata), 'io');

        final withoutMetadata = CanvasNode(
          id: 'n',
          componentId: 'lif_population',
          nirType: 'nir.Population',
          parameters: const <String, dynamic>{},
          position: const <double>[0, 0],
        );
        expect(
          GlobeLayout.defaultCategoryOf(withoutMetadata),
          'nir.Population',
        );

        final bare = CanvasNode(
          id: 'b',
          componentId: 'lif_population',
          parameters: const <String, dynamic>{},
          position: const <double>[0, 0],
        );
        expect(GlobeLayout.defaultCategoryOf(bare), 'lif_population');
      },
    );
  });

  group('GlobeLayout output helpers', () {
    test('boundingRadius is the outermost orbit radius', () {
      final layout = GlobeLayout(_singleCategory(6));
      final expected = layout.placements.values
          .map((placement) => placement.radius)
          .reduce(math.max);
      expect(layout.boundingRadius, closeTo(expected, 1e-9));
    });

    test('scaledToRadius maps the outermost node onto the target radius', () {
      final layout = GlobeLayout(_singleCategory(6));
      final scaled = layout.scaledToRadius(200);
      final outermost = scaled.values
          .map((point) => point.distance)
          .reduce(math.max);
      expect(outermost, closeTo(200, 1e-9));
      // Uniform scale preserves the relative shell structure.
      for (final entry in layout.positions.entries) {
        final original = entry.value.distance;
        final scaledDistance = scaled[entry.key]!.distance;
        expect(
          scaledDistance / original,
          closeTo(200 / layout.boundingRadius, 1e-9),
        );
      }
    });

    test('config copyWith overrides only the named fields', () {
      const config = GlobeLayoutConfig();
      final copy = config.copyWith(baseRadius: 500);
      expect(copy.baseRadius, 500);
      expect(copy.radiusJitter, config.radiusJitter);
      expect(copy.goldenTurn, config.goldenTurn);
    });
  });

  group('GlobeNetworkLayout', () {
    test('projects globe placements into 2D positions and depths', () {
      final layout = GlobeNetworkLayout(_singleCategory(4));
      expect(layout.isSettled, isTrue);
      expect(layout.positions.length, 4);
      expect(layout.depths.length, 4);
      for (final id in layout.positions.keys) {
        expect(layout.depths[id], inInclusiveRange(0.0, 1.0));
      }
      expect(layout.bounds(), isNotNull);
    });
  });
}
