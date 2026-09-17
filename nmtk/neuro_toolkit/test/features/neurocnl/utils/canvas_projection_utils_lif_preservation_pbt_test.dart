// Task 7.3 — PBT: LIF-only graphs produce identical output before and after fix
//
// **Validates: Requirements 3.1, 3.5**
//
// Property 2: Preservation — Pure-LIF Identical Output
//
// For any `CanvasProjection` where all nodes have `nirType == 'nir.LIF'` OR
// `nirType == null` (pre-fix backend fallback), the fixed
// `canvasGraphFromCanonical` MUST produce a `CanvasGraph` identical to the
// baseline recorded in task 2 — same `componentId`, same `nirType`, same
// parameters, same edges.
//
// This is the Dart-side companion to the Python preservation property. It
// extends the task 2 P-PRES-2 test by explicitly covering:
//   - Nodes with `nirType == 'nir.LIF'` (explicit, post-fix backend)
//   - Nodes with `nirType == null` (implicit, pre-fix backend fallback)
//   - Mixed projections: some nodes null, some 'nir.LIF' — all treated identically
//
// Sub-properties:
//   P7-PRES-1  Explicit `nirType == 'nir.LIF'` nodes resolve to
//              `componentId == 'lif_population'` and `nirType == 'nir.LIF'`.
//   P7-PRES-2  Null-nirType nodes (pre-fix backend) still resolve to
//              `componentId == 'lif_population'` and `nirType == 'nir.LIF'`.
//   P7-PRES-3  Mixed null + 'nir.LIF' projections: all nodes resolve identically.
//   P7-PRES-4  Parameters are preserved bitwise: name, n_neurons, threshold,
//              tau_rc match projection values for all LIF-only inputs.
//   P7-PRES-5  Edge count and identity preserved for LIF-only projections.
//   P7-PRES-6  Position logic unchanged: first-use uses index-based default;
//              existing positions are reused from `currentGraph`.
//
// Run on FIXED code.
// EXPECTED OUTCOME: ALL tests PASS.

import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical;
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart';

// ---------------------------------------------------------------------------
// Constants — expected values for all LIF-only inputs
// ---------------------------------------------------------------------------

const String _expectedComponentId = 'lif_population';
const String _expectedNirType = 'nir.LIF';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Empty [CanvasGraph] — no prior positions influence tests.
CanvasGraph get _emptyGraph => CanvasGraph(
  nodes: const <CanvasNode>[],
  edges: const <CanvasEdge>[],
  metadata: const <String, dynamic>{},
);

/// Build a projection with explicit `nirType == 'nir.LIF'` on every node.
canonical.CanvasProjection _explicitLifProjection({
  required int nodeCount,
  int size = 1,
  double? threshold,
  double? tau,
}) {
  return canonical.CanvasProjection(
    nodes: List<canonical.CanvasNode>.generate(
      nodeCount,
      (i) => canonical.CanvasNode(
        id: 'lif_$i',
        label: 'LIF_$i',
        nirType: 'nir.LIF', // explicit — post-fix backend emits this
        size: size,
        threshold: threshold,
        tau: tau,
      ),
    ),
    edges: const <canonical.CanvasEdge>[],
  );
}

/// Build a projection with `nirType == null` on every node (pre-fix backend).
canonical.CanvasProjection _nullNirTypeProjection({
  required int nodeCount,
  int size = 1,
  double? threshold,
  double? tau,
}) {
  return canonical.CanvasProjection(
    nodes: List<canonical.CanvasNode>.generate(
      nodeCount,
      (i) => canonical.CanvasNode(
        id: 'lif_$i',
        label: 'LIF_$i',
        // nirType intentionally absent — pre-fix backend path
        size: size,
        threshold: threshold,
        tau: tau,
      ),
    ),
    edges: const <canonical.CanvasEdge>[],
  );
}

/// Build a mixed projection: even-indexed nodes get explicit 'nir.LIF',
/// odd-indexed nodes get null nirType.
canonical.CanvasProjection _mixedLifProjection({
  required int nodeCount,
  int size = 1,
}) {
  return canonical.CanvasProjection(
    nodes: List<canonical.CanvasNode>.generate(
      nodeCount,
      (i) => canonical.CanvasNode(
        id: 'lif_$i',
        label: 'LIF_$i',
        nirType: i.isEven ? 'nir.LIF' : null,
        size: size,
      ),
    ),
    edges: const <canonical.CanvasEdge>[],
  );
}

/// Assert that every node in [result] has the expected LIF baseline values.
void _assertAllNodesAreLif(
  List<CanvasNode> nodes,
  List<canonical.CanvasNode> projectionNodes, {
  required String label,
}) {
  for (var i = 0; i < projectionNodes.length; i++) {
    final node = nodes[i];
    final proj = projectionNodes[i];

    expect(
      node.componentId,
      equals(_expectedComponentId),
      reason: '$label node[$i]: componentId must be lif_population',
    );
    expect(
      node.nirType,
      equals(_expectedNirType),
      reason: '$label node[$i]: nirType must be nir.LIF',
    );
    expect(
      node.parameters['name'],
      equals(proj.label),
      reason: '$label node[$i]: parameters.name must equal projection label',
    );
    expect(
      node.parameters['n_neurons'],
      equals(proj.size),
      reason:
          '$label node[$i]: parameters.n_neurons must equal projection size',
    );
  }
}

// ---------------------------------------------------------------------------
// P7-PRES-1: Explicit nirType == 'nir.LIF' nodes
// ---------------------------------------------------------------------------

void _testExplicitLifNodes() {
  group('P7-PRES-1 — Explicit nirType==nir.LIF nodes resolve to '
      'componentId=lif_population and nirType=nir.LIF', () {
    const nodeCounts = <int>[0, 1, 2, 5, 10];
    const sizes = <int>[1, 10, 128, 1000];
    const thresholds = <double?>[null, 0.0, 0.5, 1.0];
    const taus = <double?>[null, 0.01, 0.02];

    for (final n in nodeCounts) {
      for (final size in sizes) {
        for (final threshold in thresholds) {
          for (final tau in taus) {
            final label =
                'P7-PRES-1 n=$n size=$size threshold=$threshold tau=$tau';
            test(label, () {
              final projection = _explicitLifProjection(
                nodeCount: n,
                size: size,
                threshold: threshold,
                tau: tau,
              );

              final result = canvasGraphFromCanonical(
                projection,
                currentGraph: _emptyGraph,
              );

              expect(
                result.nodes,
                hasLength(n),
                reason: '$label: node count must equal projection node count',
              );

              _assertAllNodesAreLif(
                result.nodes,
                projection.nodes,
                label: label,
              );

              // Verify optional parameters
              for (var i = 0; i < n; i++) {
                final node = result.nodes[i];
                if (threshold != null) {
                  expect(
                    node.parameters['threshold'],
                    equals(threshold),
                    reason: '$label node[$i]: threshold must be preserved',
                  );
                } else {
                  expect(
                    node.parameters.containsKey('threshold'),
                    isFalse,
                    reason:
                        '$label node[$i]: threshold must be absent when null',
                  );
                }
                if (tau != null) {
                  expect(
                    node.parameters['tau_rc'],
                    equals(tau),
                    reason: '$label node[$i]: tau_rc must be preserved',
                  );
                } else {
                  expect(
                    node.parameters.containsKey('tau_rc'),
                    isFalse,
                    reason: '$label node[$i]: tau_rc must be absent when null',
                  );
                }
              }
            });
          }
        }
      }
    }
  });
}

// ---------------------------------------------------------------------------
// P7-PRES-2: Null-nirType nodes (pre-fix backend fallback)
// ---------------------------------------------------------------------------

void _testNullNirTypeNodes() {
  group('P7-PRES-2 — Null-nirType nodes (pre-fix backend) still resolve to '
      'componentId=lif_population and nirType=nir.LIF', () {
    const nodeCounts = <int>[0, 1, 2, 5, 10];
    const sizes = <int>[1, 10, 128];

    for (final n in nodeCounts) {
      for (final size in sizes) {
        final label = 'P7-PRES-2 n=$n size=$size';
        test(label, () {
          final projection = _nullNirTypeProjection(nodeCount: n, size: size);

          final result = canvasGraphFromCanonical(
            projection,
            currentGraph: _emptyGraph,
          );

          expect(
            result.nodes,
            hasLength(n),
            reason: '$label: node count must match',
          );

          _assertAllNodesAreLif(result.nodes, projection.nodes, label: label);
        });
      }
    }
  });
}

// ---------------------------------------------------------------------------
// P7-PRES-3: Mixed null + 'nir.LIF' projections
// ---------------------------------------------------------------------------

void _testMixedNullAndExplicitLif() {
  group(
    'P7-PRES-3 — Mixed null and explicit nir.LIF nodes: all resolve identically',
    () {
      const nodeCounts = <int>[2, 3, 4, 6, 10];

      for (final n in nodeCounts) {
        final label = 'P7-PRES-3 n=$n (mixed null+nir.LIF)';
        test(label, () {
          final projection = _mixedLifProjection(nodeCount: n);

          final result = canvasGraphFromCanonical(
            projection,
            currentGraph: _emptyGraph,
          );

          expect(
            result.nodes,
            hasLength(n),
            reason: '$label: node count must match',
          );

          // Every node — regardless of whether its nirType was null or 'nir.LIF'
          // — must resolve to the same LIF baseline.
          _assertAllNodesAreLif(result.nodes, projection.nodes, label: label);
        });
      }
    },
  );
}

// ---------------------------------------------------------------------------
// P7-PRES-4: Explicit 'nir.LIF' output is bitwise-identical to null fallback
// ---------------------------------------------------------------------------
//
// The most critical preservation check: for the same logical projection
// (same id, label, size, threshold, tau) the result must be identical whether
// the node carries nirType='nir.LIF' or nirType=null.

void _testExplicitEqualsNullFallback() {
  group('P7-PRES-4 — Explicit nirType==nir.LIF output is bitwise-identical to '
      'null-nirType fallback output', () {
    const nodeCounts = <int>[1, 2, 5];
    const sizes = <int>[1, 50, 200];
    const thresholds = <double?>[null, 0.5];
    const taus = <double?>[null, 0.02];

    for (final n in nodeCounts) {
      for (final size in sizes) {
        for (final threshold in thresholds) {
          for (final tau in taus) {
            final label =
                'P7-PRES-4 n=$n size=$size threshold=$threshold tau=$tau';
            test(label, () {
              final explicitProjection = _explicitLifProjection(
                nodeCount: n,
                size: size,
                threshold: threshold,
                tau: tau,
              );
              final nullProjection = _nullNirTypeProjection(
                nodeCount: n,
                size: size,
                threshold: threshold,
                tau: tau,
              );

              final explicitResult = canvasGraphFromCanonical(
                explicitProjection,
                currentGraph: _emptyGraph,
              );
              final nullResult = canvasGraphFromCanonical(
                nullProjection,
                currentGraph: _emptyGraph,
              );

              expect(
                explicitResult.nodes.length,
                equals(nullResult.nodes.length),
                reason: '$label: node count must match across both inputs',
              );

              for (var i = 0; i < n; i++) {
                final eNode = explicitResult.nodes[i];
                final nNode = nullResult.nodes[i];

                expect(
                  eNode.componentId,
                  equals(nNode.componentId),
                  reason:
                      '$label node[$i]: componentId must be identical '
                      'for explicit-nir.LIF vs null-nirType',
                );
                expect(
                  eNode.nirType,
                  equals(nNode.nirType),
                  reason:
                      '$label node[$i]: nirType must be identical '
                      'for explicit-nir.LIF vs null-nirType',
                );
                expect(
                  eNode.parameters,
                  equals(nNode.parameters),
                  reason:
                      '$label node[$i]: parameters must be identical '
                      'for explicit-nir.LIF vs null-nirType',
                );
                expect(
                  eNode.position,
                  equals(nNode.position),
                  reason:
                      '$label node[$i]: position must be identical '
                      'for explicit-nir.LIF vs null-nirType',
                );
              }

              // Edges must also be identical
              expect(
                explicitResult.edges.length,
                equals(nullResult.edges.length),
                reason: '$label: edge count must match',
              );
            });
          }
        }
      }
    }
  });
}

// ---------------------------------------------------------------------------
// P7-PRES-5: Edge count and identity for LIF-only projections
// ---------------------------------------------------------------------------
//
// Complements the P-PRES-3 edge count test from task 2 but scoped to
// explicitly LIF-typed projections.

void _testEdgeCountForLifProjections() {
  group(
    'P7-PRES-5 — Edge count and identity preserved for LIF-only projections',
    () {
      final edgeSets = <List<({String source, String target, double? weight})>>[
        [],
        [(source: 'lif_0', target: 'lif_1', weight: null)],
        [(source: 'lif_0', target: 'lif_1', weight: 0.5)],
        [(source: 'lif_0', target: 'lif_1', weight: -1.0)],
        [
          (source: 'lif_0', target: 'lif_1', weight: 1.0),
          (source: 'lif_1', target: 'lif_2', weight: null),
        ],
        [
          (source: 'lif_0', target: 'lif_1', weight: 0.3),
          (source: 'lif_1', target: 'lif_2', weight: 0.4),
          (source: 'lif_2', target: 'lif_0', weight: 0.5),
        ],
        // 5-edge fan-out
        [
          (source: 'lif_0', target: 'lif_1', weight: 0.1),
          (source: 'lif_0', target: 'lif_2', weight: 0.2),
          (source: 'lif_0', target: 'lif_3', weight: 0.3),
          (source: 'lif_0', target: 'lif_4', weight: 0.4),
          (source: 'lif_0', target: 'lif_5', weight: 0.5),
        ],
      ];

      for (final edges in edgeSets) {
        final n = edges.length;
        final label = 'P7-PRES-5 ${n == 0 ? "0 edges" : "$n edge(s)"}';

        test(label, () {
          // Collect all node ids referenced by edges
          final nodeIds = <String>{};
          for (final e in edges) {
            nodeIds.add(e.source);
            nodeIds.add(e.target);
          }
          if (nodeIds.isEmpty) nodeIds.add('lif_0');

          final projection = canonical.CanvasProjection(
            nodes: nodeIds
                .toList()
                .map(
                  (id) => canonical.CanvasNode(
                    id: id,
                    label: id,
                    nirType: 'nir.LIF', // explicit LIF for all nodes
                  ),
                )
                .toList(),
            edges: edges
                .map(
                  (e) => canonical.CanvasEdge(
                    source: e.source,
                    target: e.target,
                    weight: e.weight,
                  ),
                )
                .toList(),
          );

          final result = canvasGraphFromCanonical(
            projection,
            currentGraph: _emptyGraph,
          );

          expect(
            result.edges,
            hasLength(n),
            reason: '$label: edge count must equal projection edge count',
          );

          for (var i = 0; i < n; i++) {
            final resultEdge = result.edges[i];
            final projEdge = edges[i];

            expect(
              resultEdge.sourceNodeId,
              equals(projEdge.source),
              reason: '$label edge[$i]: sourceNodeId must match',
            );
            expect(
              resultEdge.targetNodeId,
              equals(projEdge.target),
              reason: '$label edge[$i]: targetNodeId must match',
            );
            if (projEdge.weight != null) {
              expect(
                resultEdge.parameters['weight'],
                equals(projEdge.weight),
                reason: '$label edge[$i]: weight must match',
              );
            } else {
              expect(
                resultEdge.parameters.containsKey('weight'),
                isFalse,
                reason: '$label edge[$i]: weight must be absent when null',
              );
            }
          }
        });
      }
    },
  );
}

// ---------------------------------------------------------------------------
// P7-PRES-6: Position logic unchanged for LIF-only projections
// ---------------------------------------------------------------------------

void _testPositionLogicPreserved() {
  group(
    'P7-PRES-6 — Position logic unchanged for explicit nirType==nir.LIF nodes',
    () {
      test('single explicit-LIF node: position defaults to [80.0, 160.0]', () {
        final projection = const canonical.CanvasProjection(
          nodes: <canonical.CanvasNode>[
            canonical.CanvasNode(
              id: 'lif_0',
              label: 'LIF_0',
              nirType: 'nir.LIF',
              size: 50,
              threshold: 0.5,
              tau: 0.02,
            ),
          ],
          edges: <canonical.CanvasEdge>[],
        );

        final result = canvasGraphFromCanonical(
          projection,
          currentGraph: _emptyGraph,
        );

        expect(
          result.nodes.first.position,
          equals(<double>[80.0, 160.0]),
          reason:
              'P7-PRES-6: first node position must be [80.0, 160.0] '
              'when no prior graph exists',
        );
      });

      test('three explicit-LIF nodes: positions are [80, 300, 520] x 160', () {
        final projection = _explicitLifProjection(nodeCount: 3);
        final result = canvasGraphFromCanonical(
          projection,
          currentGraph: _emptyGraph,
        );

        expect(result.nodes, hasLength(3));
        expect(
          result.nodes[0].position,
          equals(<double>[80.0, 160.0]),
          reason: 'P7-PRES-6: node[0] position',
        );
        expect(
          result.nodes[1].position,
          equals(<double>[300.0, 160.0]),
          reason: 'P7-PRES-6: node[1] position = 80 + 220 = 300',
        );
        expect(
          result.nodes[2].position,
          equals(<double>[520.0, 160.0]),
          reason: 'P7-PRES-6: node[2] position = 80 + 440 = 520',
        );
      });

      test(
        'position is reused from currentGraph when explicit-LIF node id exists',
        () {
          final prior = CanvasGraph(
            nodes: <CanvasNode>[
              CanvasNode(
                id: 'lif_0',
                componentId: 'lif_population',
                nirType: 'nir.LIF',
                label: 'LIF_0',
                parameters: const <String, dynamic>{},
                position: const <double>[999.0, 888.0],
              ),
            ],
            edges: const <CanvasEdge>[],
            metadata: const <String, dynamic>{},
          );

          final projection = const canonical.CanvasProjection(
            nodes: <canonical.CanvasNode>[
              canonical.CanvasNode(
                id: 'lif_0',
                label: 'LIF_0',
                nirType: 'nir.LIF',
              ),
            ],
            edges: <canonical.CanvasEdge>[],
          );

          final result = canvasGraphFromCanonical(
            projection,
            currentGraph: prior,
          );

          expect(
            result.nodes.first.position,
            equals(<double>[999.0, 888.0]),
            reason:
                'P7-PRES-6: position must be reused from currentGraph '
                'when explicit-LIF node id matches',
          );
        },
      );
    },
  );
}

// ---------------------------------------------------------------------------
// main — wire up all sub-properties
// ---------------------------------------------------------------------------

void main() {
  _testExplicitLifNodes();
  _testNullNirTypeNodes();
  _testMixedNullAndExplicitLif();
  _testExplicitEqualsNullFallback();
  _testEdgeCountForLifProjections();
  _testPositionLogicPreserved();
}
