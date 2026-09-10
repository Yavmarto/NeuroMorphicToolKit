// Unit tests for the client-side force-directed layout engine:
// repulsion + edge-spring + centering over a CanvasGraph, plus the topology
// depth model and the viewport fit. These pin down the deterministic,
// settle-to-stable behaviour the 2.5D network view relies on.

import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/force_directed_layout.dart';

CanvasNode _node(
  String id, {
  String? nirType,
  Map<String, dynamic> parameters = const {},
}) {
  return CanvasNode(
    id: id,
    componentId: nirType ?? 'lif_population',
    nirType: nirType,
    label: id,
    parameters: parameters,
    position: const <double>[0, 0],
  );
}

CanvasEdge _edge(String id, String source, String target) {
  return CanvasEdge(
    id: id,
    sourceNodeId: source,
    sourcePort: 'out',
    targetNodeId: target,
    targetPort: 'in',
    parameters: const <String, dynamic>{},
  );
}

CanvasGraph _chainGraph() {
  return CanvasGraph(
    nodes: [
      _node('input', nirType: 'nir.Input'),
      _node('h1'),
      _node('h2'),
      _node('output', nirType: 'nir.Output'),
    ],
    edges: [
      _edge('e1', 'input', 'h1'),
      _edge('e2', 'h1', 'h2'),
      _edge('e3', 'h2', 'output'),
    ],
    metadata: const <String, dynamic>{},
  );
}

double _distance(Offset a, Offset b) => (a - b).distance;

void main() {
  group('ForceDirectedLayout', () {
    test('is deterministic: same graph yields identical positions', () {
      final graph = _chainGraph();
      final a = ForceDirectedLayout(graph)..relax();
      final b = ForceDirectedLayout(graph)..relax();
      expect(a.positions.keys, b.positions.keys);
      for (final id in graph.nodes.map((node) => node.id)) {
        expect(
          (a.positions[id]! - b.positions[id]!).distance,
          lessThan(1e-9),
          reason: '$id diverged between two runs',
        );
      }
    });

    test('settles to finite, bounded positions', () {
      final layout = ForceDirectedLayout(_chainGraph())..relax();
      expect(layout.isSettled, isTrue);
      expect(layout.iterations, greaterThan(0));
      for (final id in layout.positions.keys) {
        final p = layout.positions[id]!;
        expect(p.dx.isFinite, isTrue);
        expect(p.dy.isFinite, isTrue);
        expect(p.distance, lessThan(2000));
      }
    });

    test('respects a minimum pairwise separation', () {
      final layout = ForceDirectedLayout(_chainGraph())..relax();
      final positions = layout.positions.values.toList();
      var minDistance = double.infinity;
      for (var i = 0; i < positions.length; i++) {
        for (var j = i + 1; j < positions.length; j++) {
          minDistance = _min(
            minDistance,
            _distance(positions[i], positions[j]),
          );
        }
      }
      expect(minDistance, greaterThan(15));
    });

    test('clusters connected pairs closer than disconnected pairs', () {
      // Two independent connected pairs; no edge between the pairs.
      final graph = CanvasGraph(
        nodes: [_node('a'), _node('b'), _node('c'), _node('d')],
        edges: [_edge('ab', 'a', 'b'), _edge('cd', 'c', 'd')],
        metadata: const <String, dynamic>{},
      );
      final layout = ForceDirectedLayout(graph)..relax();
      final positions = layout.positions;

      final intra = [
        _distance(positions['a']!, positions['b']!),
        _distance(positions['c']!, positions['d']!),
      ];
      final inter = [
        _distance(positions['a']!, positions['c']!),
        _distance(positions['a']!, positions['d']!),
        _distance(positions['b']!, positions['c']!),
        _distance(positions['b']!, positions['d']!),
      ];
      final intraAvg = intra.reduce((x, y) => x + y) / intra.length;
      final interAvg = inter.reduce((x, y) => x + y) / inter.length;
      expect(intraAvg, lessThan(interAvg * 0.8));
    });

    test('connected nodes settle near the spring rest length', () {
      final layout = ForceDirectedLayout(_chainGraph())..relax();
      final positions = layout.positions;
      for (final edge in _chainGraph().edges) {
        final d = _distance(
          positions[edge.sourceNodeId]!,
          positions[edge.targetNodeId]!,
        );
        expect(d, lessThan(140));
        expect(d, greaterThan(40));
      }
    });

    test('pinned nodes do not move during relaxation', () {
      final graph = _chainGraph();
      final layout = ForceDirectedLayout(graph);
      final original = layout.positions['h1']!;
      layout.pin('h1', original);
      layout.relax();
      expect((layout.positions['h1']! - original).distance, lessThan(1e-9));
    });

    test('updateGraph preserves surviving node positions', () {
      final before = _chainGraph();
      final layout = ForceDirectedLayout(before);
      layout.pin('h1', layout.positions['h1']!);
      layout.relax();
      final snapshot = Map<String, Offset>.from(layout.positions);

      final after = CanvasGraph(
        nodes: [...before.nodes, _node('extra')],
        edges: before.edges,
        metadata: const <String, dynamic>{},
      );
      layout.updateGraph(after);
      layout.relax();

      // The pinned node cannot move at all.
      expect(
        (layout.positions['h1']! - snapshot['h1']!).distance,
        lessThan(1.0),
      );
      // Survivors shift only to make room for the new node — a re-seed from the
      // spiral would move them an order of magnitude more.
      for (final id in before.nodes.map((node) => node.id)) {
        expect(
          (layout.positions[id]! - snapshot[id]!).distance,
          lessThan(80.0),
          reason: '$id should have been preserved across the topology change',
        );
      }
      expect(layout.positions.containsKey('extra'), isTrue);
    });

    test(
      'fitToSize maps positions inside the target bounds and centres them',
      () {
        final layout = ForceDirectedLayout(_chainGraph())..relax();
        const size = Size(800, 600);
        const padding = 64.0;
        final fitted = layout.fitToSize(size, padding: padding);
        for (final offset in fitted.values) {
          expect(offset.dx, greaterThanOrEqualTo(-0.01));
          expect(offset.dx, lessThanOrEqualTo(800.01));
          expect(offset.dy, greaterThanOrEqualTo(-0.01));
          expect(offset.dy, lessThanOrEqualTo(600.01));
        }
        final box = _boundsOf(fitted.values);
        expect(box.center.dx, closeTo(400, 1));
        expect(box.center.dy, closeTo(300, 1));
      },
    );

    test('empty graph is a no-op', () {
      final layout = ForceDirectedLayout(
        CanvasGraph(nodes: [], edges: [], metadata: {}),
      )..relax();
      expect(layout.positions, isEmpty);
      expect(layout.bounds(), isNull);
      expect(layout.fitToSize(const Size(100, 100)), isEmpty);
      expect(layout.isSettled, isTrue);
    });

    test('config copyWith overrides only the named fields', () {
      const config = ForceDirectedLayoutConfig();
      final copy = config.copyWith(springLength: 200);
      expect(copy.springLength, 200);
      expect(copy.repulsion, config.repulsion);
      expect(copy.damping, config.damping);
    });
  });

  group('computeNetworkDepths', () {
    test('sources are nearest, sinks recede, values stay in 0..1', () {
      final graph = _chainGraph();
      final depths = computeNetworkDepths(graph);
      expect(depths['input']! > depths['h1']!, isTrue);
      expect(depths['h1']! > depths['h2']!, isTrue);
      expect(depths['h2']! > depths['output']!, isTrue);
      for (final value in depths.values) {
        expect(value, inInclusiveRange(0.0, 1.0));
      }
    });

    test('is deterministic', () {
      final graph = _chainGraph();
      expect(computeNetworkDepths(graph), computeNetworkDepths(graph));
    });

    test('isolated graph without edges still yields depths', () {
      final graph = CanvasGraph(
        nodes: [_node('a'), _node('b')],
        edges: const <CanvasEdge>[],
        metadata: const <String, dynamic>{},
      );
      final depths = computeNetworkDepths(graph);
      expect(depths.keys.toSet(), {'a', 'b'});
      for (final value in depths.values) {
        expect(value, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}

double _min(double a, double b) => a < b ? a : b;

Rect _boundsOf(Iterable<Offset> offsets) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final offset in offsets) {
    minX = _min(minX, offset.dx);
    minY = _min(minY, offset.dy);
    maxX = _max(maxX, offset.dx);
    maxY = _max(maxY, offset.dy);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

double _max(double a, double b) => a > b ? a : b;
