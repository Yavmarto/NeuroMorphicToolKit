// Property-Based Test — Edge Count Preservation for Arbitrary Projections
//
// **Validates: Requirements 2.3, 3.1**
//
// Task 7.2 — Property 2: Preservation
//   Edge Count Preserved Through canvasGraphFromCanonical
//
// For any CanvasProjection with 0–20 random edges (random sourceNodeId,
// targetNodeId, weight), asserts:
//   1. canvasGraphFromCanonical(projection).edges.length == projection.edges.length
//   2. Each edge's sourceNodeId, targetNodeId, weight match the projection.
//
// Run on FIXED code. EXPECTED OUTCOME: ALL tests PASS.
//
// Strategy: use dart:math Random with a fixed seed to generate 100 pseudo-random
// CanvasProjection instances, each with a random edge count in [0, 20] and random
// edge fields (sourceNodeId, targetNodeId, weight). This covers the full 0–20 range
// with diverse node id strings and weight values including null, positive, negative,
// and zero weights — a larger and more random input space than the fixed edge sets
// in P-PRES-3.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical;
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Fixed seed ensures deterministic test runs across CI and local machines.
const int _seed = 0xDEADCAFE;

/// Number of pseudo-random projections to generate per sub-property run.
const int _trialCount = 100;

/// Maximum number of edges per generated projection (inclusive).
const int _maxEdges = 20;

/// Maximum number of distinct node id labels in the pool per projection.
const int _nodePoolSize = 8;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pool of node id strings used to generate random sourceNodeId / targetNodeId.
/// Using a small pool ensures cross-edge references (fan-out, chains, etc.)
/// arise naturally in the random input space.
List<String> _nodeIdPool(int size) =>
    List<String>.generate(size, (i) => 'n${i.toString().padLeft(2, '0')}');

/// Generates a random weight: null (25 %), or a double in [-200.0, 200.0].
double? _randomWeight(Random rng) {
  final roll = rng.nextInt(4);
  if (roll == 0) return null;
  // Map [0.0, 1.0) → [-200.0, 200.0)
  return (rng.nextDouble() * 400.0) - 200.0;
}

/// Builds a [canonical.CanvasProjection] with [edgeCount] random edges drawn
/// from [pool] and null-free [CanvasNode] stubs for every referenced node id.
canonical.CanvasProjection _randomProjection({
  required Random rng,
  required int edgeCount,
  required List<String> pool,
}) {
  final edges = <canonical.CanvasEdge>[];
  for (var i = 0; i < edgeCount; i++) {
    final source = pool[rng.nextInt(pool.length)];
    final target = pool[rng.nextInt(pool.length)];
    edges.add(
      canonical.CanvasEdge(
        source: source,
        target: target,
        weight: _randomWeight(rng),
      ),
    );
  }

  // Collect unique node ids from edges; always include at least one node.
  final nodeIds = <String>{};
  for (final e in edges) {
    nodeIds
      ..add(e.source)
      ..add(e.target);
  }
  if (nodeIds.isEmpty) nodeIds.add(pool.first);

  final nodes = nodeIds.toList()..sort();

  return canonical.CanvasProjection(
    nodes: nodes.map((id) => canonical.CanvasNode(id: id, label: id)).toList(),
    edges: edges,
  );
}

/// Empty [CanvasGraph] — no prior positions, so position logic does not
/// interfere with the edge-count or edge-identity assertions.
CanvasGraph get _emptyGraph => CanvasGraph(
  nodes: const <CanvasNode>[],
  edges: const <CanvasEdge>[],
  metadata: const <String, dynamic>{},
);

// ---------------------------------------------------------------------------
// P-PBT-EDGE-1: Edge count preserved
// ---------------------------------------------------------------------------
//
// **Validates: Requirements 2.3, 3.1**
//
// For any CanvasProjection with 0–20 random edges,
// canvasGraphFromCanonical(projection).edges.length == projection.edges.length.

void _testEdgeCountPreservation() {
  group('P-PBT-EDGE-1 — Edge count preserved: '
      'result.edges.length == projection.edges.length '
      'for 0–$_maxEdges random edges over $_trialCount trials', () {
    test('P-PBT-EDGE-1: edge count is preserved across $_trialCount random '
        'projections with 0–$_maxEdges edges each', () {
      final rng = Random(_seed);
      final pool = _nodeIdPool(_nodePoolSize);

      for (var trial = 0; trial < _trialCount; trial++) {
        final edgeCount = rng.nextInt(_maxEdges + 1); // [0, 20]
        final projection = _randomProjection(
          rng: rng,
          edgeCount: edgeCount,
          pool: pool,
        );

        final result = canvasGraphFromCanonical(
          projection,
          currentGraph: _emptyGraph,
        );

        expect(
          result.edges.length,
          equals(edgeCount),
          reason:
              'P-PBT-EDGE-1 trial $trial (edgeCount=$edgeCount): '
              'result.edges.length (${result.edges.length}) must equal '
              'projection.edges.length ($edgeCount)',
        );
      }
    });
  });
}

// ---------------------------------------------------------------------------
// P-PBT-EDGE-2: Edge identity preserved (sourceNodeId, targetNodeId, weight)
// ---------------------------------------------------------------------------
//
// **Validates: Requirements 2.3**
//
// For any CanvasProjection with 0–20 random edges, each result edge at index i
// must satisfy:
//   result.edges[i].sourceNodeId == projection.edges[i].source
//   result.edges[i].targetNodeId == projection.edges[i].target
//   result.edges[i].parameters['weight'] == projection.edges[i].weight
//     (or parameters must NOT contain 'weight' when projection weight is null)

void _testEdgeIdentityPreservation() {
  group('P-PBT-EDGE-2 — Edge identity preserved: '
      'sourceNodeId, targetNodeId, weight match for each edge '
      'over $_trialCount random trials', () {
    test(
      'P-PBT-EDGE-2: each edge\'s sourceNodeId, targetNodeId, and weight '
      'match the projection across $_trialCount trials with 0–$_maxEdges edges',
      () {
        // Use a different but deterministic seed offset so this property
        // exercises a non-overlapping region of the random input space.
        final rng = Random(_seed ^ 0x12345678);
        final pool = _nodeIdPool(_nodePoolSize);

        for (var trial = 0; trial < _trialCount; trial++) {
          final edgeCount = rng.nextInt(_maxEdges + 1); // [0, 20]
          final projection = _randomProjection(
            rng: rng,
            edgeCount: edgeCount,
            pool: pool,
          );

          final result = canvasGraphFromCanonical(
            projection,
            currentGraph: _emptyGraph,
          );

          for (var i = 0; i < edgeCount; i++) {
            final resultEdge = result.edges[i];
            final projEdge = projection.edges[i];

            expect(
              resultEdge.sourceNodeId,
              equals(projEdge.source),
              reason:
                  'P-PBT-EDGE-2 trial $trial edge $i: '
                  'sourceNodeId mismatch — '
                  'got "${resultEdge.sourceNodeId}", '
                  'expected "${projEdge.source}"',
            );

            expect(
              resultEdge.targetNodeId,
              equals(projEdge.target),
              reason:
                  'P-PBT-EDGE-2 trial $trial edge $i: '
                  'targetNodeId mismatch — '
                  'got "${resultEdge.targetNodeId}", '
                  'expected "${projEdge.target}"',
            );

            if (projEdge.weight != null) {
              expect(
                resultEdge.parameters['weight'],
                equals(projEdge.weight),
                reason:
                    'P-PBT-EDGE-2 trial $trial edge $i: '
                    'weight mismatch — '
                    "got ${resultEdge.parameters['weight']}, "
                    'expected ${projEdge.weight}',
              );
            } else {
              expect(
                resultEdge.parameters.containsKey('weight'),
                isFalse,
                reason:
                    'P-PBT-EDGE-2 trial $trial edge $i: '
                    'parameters must NOT contain "weight" when '
                    'projection edge weight is null',
              );
            }
          }
        }
      },
    );
  });
}

// ---------------------------------------------------------------------------
// P-PBT-EDGE-3: Zero-edge projections
// ---------------------------------------------------------------------------
//
// **Validates: Requirements 2.3**
//
// A projection with 0 edges must always produce a result with 0 edges,
// independent of node count. Exercised separately to ensure the 0-edge
// boundary case is always covered even if the random trials above happen
// not to pick edgeCount==0 often.

void _testZeroEdgeBoundary() {
  group('P-PBT-EDGE-3 — Zero-edge boundary: '
      'projections with 0 edges always produce 0 result edges', () {
    const nodeCounts = <int>[0, 1, 2, 5, 10, 20];

    for (final n in nodeCounts) {
      test('P-PBT-EDGE-3 [$n node(s)]: 0 edges in → 0 edges out', () {
        final nodes = List<canonical.CanvasNode>.generate(
          n,
          (i) => canonical.CanvasNode(id: 'node_$i', label: 'Node $i'),
        );

        final projection = canonical.CanvasProjection(
          nodes: nodes,
          edges: const <canonical.CanvasEdge>[],
        );

        final result = canvasGraphFromCanonical(
          projection,
          currentGraph: _emptyGraph,
        );

        expect(
          result.edges,
          isEmpty,
          reason:
              'P-PBT-EDGE-3 [$n node(s)]: '
              'a projection with 0 edges must produce a result with 0 edges',
        );
      });
    }
  });
}

// ---------------------------------------------------------------------------
// P-PBT-EDGE-4: Exact 20-edge boundary
// ---------------------------------------------------------------------------
//
// **Validates: Requirements 2.3**
//
// Explicitly exercises the maximum edge count (20) to confirm the upper
// boundary of the 0–20 range is handled correctly.

void _testMaxEdgeBoundary() {
  group('P-PBT-EDGE-4 — Max-edge boundary: '
      'projections with exactly 20 edges preserve all 20 edges', () {
    test('P-PBT-EDGE-4: 20 random edges — count and identity preserved', () {
      final rng = Random(_seed ^ 0xABCDEF01);
      final pool = _nodeIdPool(_nodePoolSize);

      // Run 10 distinct 20-edge projections to confirm the boundary.
      for (var trial = 0; trial < 10; trial++) {
        final projection = _randomProjection(
          rng: rng,
          edgeCount: 20,
          pool: pool,
        );

        final result = canvasGraphFromCanonical(
          projection,
          currentGraph: _emptyGraph,
        );

        expect(
          result.edges.length,
          equals(20),
          reason:
              'P-PBT-EDGE-4 trial $trial: '
              'result must contain exactly 20 edges',
        );

        for (var i = 0; i < 20; i++) {
          expect(
            result.edges[i].sourceNodeId,
            equals(projection.edges[i].source),
            reason: 'P-PBT-EDGE-4 trial $trial edge $i: sourceNodeId mismatch',
          );
          expect(
            result.edges[i].targetNodeId,
            equals(projection.edges[i].target),
            reason: 'P-PBT-EDGE-4 trial $trial edge $i: targetNodeId mismatch',
          );
        }
      }
    });
  });
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

void main() {
  _testEdgeCountPreservation();
  _testEdgeIdentityPreservation();
  _testZeroEdgeBoundary();
  _testMaxEdgeBoundary();
}
