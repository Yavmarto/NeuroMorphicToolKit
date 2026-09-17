// Preservation Property Tests — Pure-LIF Graphs Are Unchanged
//
// **Validates: Requirements 3.1, 3.5, 2.3**
//
// These tests are written BEFORE any fix is applied.
// They MUST PASS on unfixed code — passing confirms the baseline behaviour
// that the fix must preserve.
//
// Sub-properties:
//   P-PRES-1  Observation baseline: a specific pure-LIF projection produces the
//             exact componentId, nirType, parameter values, and position that
//             unfixed canvasGraphFromCanonical assigns.
//   P-PRES-2  (PBT) For any CanvasProjection where every node has nirType==null
//             (which is what unfixed canonical.CanvasNode provides — no field),
//             canvasGraphFromCanonical returns nodes with:
//               • componentId == 'lif_population'
//               • nirType == 'nir.LIF'
//               • parameters['name'] == projection node label
//               • parameters['n_neurons'] == projection node size
//               • optional threshold/tau_rc match projection values
//             This is the bitwise-identical preservation contract.
//   P-PRES-3  (PBT) Edge-count sub-property: for any CanvasProjection with N
//             edges, canvasGraphFromCanonical returns a CanvasGraph with exactly
//             N edges, each matching sourceNodeId, targetNodeId, weight.
//
// EXPECTED OUTCOME: ALL tests PASS on unfixed code.
// This run records the exact baseline that the fix must not change for
// pure-LIF / null-nirType inputs.

import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical;
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart';

// ---------------------------------------------------------------------------
// Constants — baseline expected values recorded from unfixed code
// ---------------------------------------------------------------------------

/// On unfixed code every node gets these hardcoded values regardless of input.
const String _baselineComponentId = 'lif_population';
const String _baselineNirType = 'nir.LIF';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a [canonical.CanvasProjection] with [nodeCount] pure-LIF nodes.
/// All nodes use default values (size=1, no threshold/tau) unless overridden.
canonical.CanvasProjection _pureLifProjection({
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
        size: size,
        threshold: threshold,
        tau: tau,
      ),
    ),
    edges: const <canonical.CanvasEdge>[],
  );
}

/// Build a projection with [nodeIds] and a set of directed [edges].
canonical.CanvasProjection _projectionWithEdges({
  required List<String> nodeIds,
  required List<({String source, String target, double? weight})> edges,
}) {
  return canonical.CanvasProjection(
    nodes: nodeIds
        .map((id) => canonical.CanvasNode(id: id, label: id))
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
}

/// Empty [CanvasGraph] — no prior positions interfere with tests.
CanvasGraph get _emptyGraph => CanvasGraph(
  nodes: const <CanvasNode>[],
  edges: const <CanvasEdge>[],
  metadata: const <String, dynamic>{},
);

// ---------------------------------------------------------------------------
// P-PRES-1: Observation baseline — specific pure-LIF projection
// ---------------------------------------------------------------------------
//
// Records exact output of canvasGraphFromCanonical on unfixed code.
// componentId='lif_population', nirType='nir.LIF', position auto-assigned.

void _testBaselineObservation() {
  group('P-PRES-1 — Observation baseline: specific pure-LIF projection produces '
      'expected componentId, nirType, parameters, and position', () {
    test('single node: componentId==lif_population, nirType==nir.LIF, '
        'parameters match, position=[80.0, 160.0]', () {
      final projection = const canonical.CanvasProjection(
        nodes: <canonical.CanvasNode>[
          canonical.CanvasNode(
            id: 'lif_population',
            label: 'MyLIF',
            size: 100,
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
        result.nodes,
        hasLength(1),
        reason: 'P-PRES-1: must return exactly 1 node',
      );

      final node = result.nodes.first;

      // --- Baseline componentId ---
      expect(
        node.componentId,
        equals(_baselineComponentId),
        reason:
            'P-PRES-1: unfixed code stamps componentId=lif_population; '
            'fix must preserve this for pure-LIF nodes.',
      );

      // --- Baseline nirType ---
      expect(
        node.nirType,
        equals(_baselineNirType),
        reason:
            'P-PRES-1: unfixed code stamps nirType=nir.LIF; '
            'fix must preserve this for pure-LIF / null-type nodes.',
      );

      // --- Parameters ---
      expect(
        node.parameters['name'],
        equals('MyLIF'),
        reason: 'P-PRES-1: parameters.name == projection node label',
      );
      expect(
        node.parameters['n_neurons'],
        equals(100),
        reason: 'P-PRES-1: parameters.n_neurons == projection node size',
      );
      expect(
        node.parameters['threshold'],
        equals(0.5),
        reason: 'P-PRES-1: parameters.threshold == projection threshold',
      );
      expect(
        node.parameters['tau_rc'],
        equals(0.02),
        reason: 'P-PRES-1: parameters.tau_rc == projection tau',
      );

      // --- Position (no prior graph, so index-based default) ---
      expect(
        node.position,
        equals(<double>[80.0, 160.0]),
        reason:
            'P-PRES-1: first node position defaults to [80.0, 160.0] '
            'when no prior graph supplies an existing position.',
      );
    });

    test('two nodes: positions are [80.0, 160.0] and [300.0, 160.0]', () {
      final projection = _pureLifProjection(nodeCount: 2);
      final result = canvasGraphFromCanonical(
        projection,
        currentGraph: _emptyGraph,
      );

      expect(result.nodes, hasLength(2));
      expect(
        result.nodes[0].position,
        equals(<double>[80.0, 160.0]),
        reason: 'P-PRES-1: node[0] position == [80.0, 160.0]',
      );
      expect(
        result.nodes[1].position,
        equals(<double>[300.0, 160.0]),
        reason:
            'P-PRES-1: node[1] position == [80.0 + 220.0, 160.0] = [300.0, 160.0]',
      );
    });

    test(
      'position is preserved from currentGraph when node id already exists',
      () {
        final prior = CanvasGraph(
          nodes: <CanvasNode>[
            CanvasNode(
              id: 'lif_0',
              componentId: 'lif_population',
              nirType: 'nir.LIF',
              label: 'LIF_0',
              parameters: const <String, dynamic>{},
              position: const <double>[400.0, 250.0],
            ),
          ],
          edges: const <CanvasEdge>[],
          metadata: const <String, dynamic>{},
        );

        final projection = const canonical.CanvasProjection(
          nodes: <canonical.CanvasNode>[
            canonical.CanvasNode(id: 'lif_0', label: 'LIF_0'),
          ],
          edges: <canonical.CanvasEdge>[],
        );

        final result = canvasGraphFromCanonical(
          projection,
          currentGraph: prior,
        );

        expect(
          result.nodes.first.position,
          equals(<double>[400.0, 250.0]),
          reason:
              'P-PRES-1: position is taken from currentGraph when id matches',
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// P-PRES-2: PBT — pure-LIF / null-nirType nodes are bitwise-identical
// ---------------------------------------------------------------------------
//
// **Validates: Requirements 3.1, 3.5**
//
// For any CanvasProjection where every projection node has nirType==null
// (which is what canonical.CanvasNode supplies today — no nirType field),
// canvasGraphFromCanonical must return nodes with componentId=='lif_population'
// and nirType=='nir.LIF'. This is the preservation contract for the fallback
// path that the fix introduces.
//
// We enumerate a representative input space covering:
//   - node counts: 0, 1, 2, 5, 10
//   - size values: 1, 10, 128, 1000
//   - threshold: null, 0.0, 0.5, 1.0
//   - tau: null, 0.01, 0.02

void _testPureLIFPreservation() {
  group('P-PRES-2 — PBT: pure-LIF (null-nirType) nodes produce componentId=lif_population '
      'and nirType=nir.LIF for any node count / parameter combination', () {
    // Input space samples
    const nodeCounts = <int>[0, 1, 2, 5, 10];
    const sizes = <int>[1, 10, 128, 1000];
    const thresholds = <double?>[null, 0.0, 0.5, 1.0];
    const taus = <double?>[null, 0.01, 0.02];

    for (final n in nodeCounts) {
      for (final size in sizes) {
        for (final threshold in thresholds) {
          for (final tau in taus) {
            final label = 'n=$n size=$size threshold=$threshold tau=$tau';
            test('P-PRES-2 [$label]: all nodes have componentId=lif_population '
                'and nirType=nir.LIF', () {
              final projection = _pureLifProjection(
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
                reason:
                    'P-PRES-2 [$label]: node count must equal projection node count',
              );

              for (var i = 0; i < n; i++) {
                final node = result.nodes[i];
                expect(
                  node.componentId,
                  equals(_baselineComponentId),
                  reason:
                      'P-PRES-2 [$label] node[$i]: '
                      'componentId must remain lif_population for null-nirType nodes',
                );
                expect(
                  node.nirType,
                  equals(_baselineNirType),
                  reason:
                      'P-PRES-2 [$label] node[$i]: '
                      'nirType must remain nir.LIF for null-nirType nodes',
                );
                expect(
                  node.parameters['name'],
                  equals(projection.nodes[i].label),
                  reason:
                      'P-PRES-2 [$label] node[$i]: '
                      'parameters.name must equal projection label',
                );
                expect(
                  node.parameters['n_neurons'],
                  equals(size),
                  reason:
                      'P-PRES-2 [$label] node[$i]: '
                      'parameters.n_neurons must equal projection size',
                );
                if (threshold != null) {
                  expect(
                    node.parameters['threshold'],
                    equals(threshold),
                    reason:
                        'P-PRES-2 [$label] node[$i]: '
                        'parameters.threshold must equal projection threshold',
                  );
                } else {
                  expect(
                    node.parameters.containsKey('threshold'),
                    isFalse,
                    reason:
                        'P-PRES-2 [$label] node[$i]: '
                        'parameters must NOT contain threshold when projection threshold is null',
                  );
                }
                if (tau != null) {
                  expect(
                    node.parameters['tau_rc'],
                    equals(tau),
                    reason:
                        'P-PRES-2 [$label] node[$i]: '
                        'parameters.tau_rc must equal projection tau',
                  );
                } else {
                  expect(
                    node.parameters.containsKey('tau_rc'),
                    isFalse,
                    reason:
                        'P-PRES-2 [$label] node[$i]: '
                        'parameters must NOT contain tau_rc when projection tau is null',
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
// P-PRES-3: PBT — edge-count sub-property
// ---------------------------------------------------------------------------
//
// **Validates: Requirements 2.3, 3.1**
//
// For any CanvasProjection with N edges, canvasGraphFromCanonical returns a
// CanvasGraph with exactly N edges, each matching sourceNodeId, targetNodeId,
// and weight.
//
// This covers Property 3 (edge count) and also anchors the preservation
// contract: edge handling is unchanged for any input type (LIF or non-LIF).
//
// Input space:
//   - edge counts: 0, 1, 2, 3, 5, 10
//   - weight: null, 0.0, 0.5, 1.0, -1.0, 100.0

void _testEdgeCountPreservation() {
  group('P-PRES-3 — PBT: edge count and identity preserved through '
      'canvasGraphFromCanonical for any N edges', () {
    // Each entry: (sourceId, targetId, weight)
    final edgeSets = <List<({String source, String target, double? weight})>>[
      // 0 edges
      [],
      // 1 edge
      [(source: 'a', target: 'b', weight: null)],
      [(source: 'a', target: 'b', weight: 0.5)],
      [(source: 'a', target: 'b', weight: -1.0)],
      [(source: 'a', target: 'b', weight: 0.0)],
      // 2 edges
      [
        (source: 'a', target: 'b', weight: 1.0),
        (source: 'b', target: 'c', weight: null),
      ],
      [
        (source: 'a', target: 'b', weight: null),
        (source: 'b', target: 'a', weight: null), // reverse edge
      ],
      // 3 edges
      [
        (source: 'x', target: 'y', weight: 0.1),
        (source: 'y', target: 'z', weight: 0.2),
        (source: 'x', target: 'z', weight: 0.3),
      ],
      // 5 edges — fan-out from node a
      [
        (source: 'a', target: 'b', weight: 0.5),
        (source: 'a', target: 'c', weight: 0.5),
        (source: 'a', target: 'd', weight: 0.5),
        (source: 'a', target: 'e', weight: 0.5),
        (source: 'a', target: 'f', weight: 0.5),
      ],
      // 10 edges — chain
      [
        (source: 'n0', target: 'n1', weight: null),
        (source: 'n1', target: 'n2', weight: null),
        (source: 'n2', target: 'n3', weight: null),
        (source: 'n3', target: 'n4', weight: null),
        (source: 'n4', target: 'n5', weight: null),
        (source: 'n5', target: 'n6', weight: null),
        (source: 'n6', target: 'n7', weight: null),
        (source: 'n7', target: 'n8', weight: null),
        (source: 'n8', target: 'n9', weight: null),
        (source: 'n9', target: 'n0', weight: null),
      ],
      // Weight extremes
      [(source: 'a', target: 'b', weight: 100.0)],
      [(source: 'a', target: 'b', weight: -100.0)],
    ];

    for (final edges in edgeSets) {
      final n = edges.length;
      final edgeLabel = n == 0
          ? '0 edges'
          : '$n edge(s): ${edges.map((e) => '${e.source}->${e.target}(w=${e.weight})').join(', ')}';

      test('P-PRES-3 [$edgeLabel]: result.edges.length == $n and each edge '
          'has matching sourceNodeId, targetNodeId, weight', () {
        // Collect all unique node ids referenced by edges.
        final nodeIds = <String>{};
        for (final e in edges) {
          nodeIds.add(e.source);
          nodeIds.add(e.target);
        }
        // Add at least one node if no edges.
        if (nodeIds.isEmpty) nodeIds.add('lone_node');

        final projection = _projectionWithEdges(
          nodeIds: nodeIds.toList()..sort(),
          edges: edges,
        );

        final result = canvasGraphFromCanonical(
          projection,
          currentGraph: _emptyGraph,
        );

        // --- Edge count ---
        expect(
          result.edges,
          hasLength(n),
          reason:
              'P-PRES-3: result.edges.length must equal projection.edges.length ($n)',
        );

        // --- Edge identity ---
        for (var i = 0; i < n; i++) {
          final resultEdge = result.edges[i];
          final projEdge = edges[i];

          expect(
            resultEdge.sourceNodeId,
            equals(projEdge.source),
            reason:
                'P-PRES-3 edge[$i]: sourceNodeId must equal projection source',
          );
          expect(
            resultEdge.targetNodeId,
            equals(projEdge.target),
            reason:
                'P-PRES-3 edge[$i]: targetNodeId must equal projection target',
          );

          if (projEdge.weight != null) {
            expect(
              resultEdge.parameters['weight'],
              equals(projEdge.weight),
              reason:
                  'P-PRES-3 edge[$i]: parameters.weight must equal projection weight',
            );
          } else {
            expect(
              resultEdge.parameters.containsKey('weight'),
              isFalse,
              reason:
                  'P-PRES-3 edge[$i]: parameters must NOT contain weight '
                  'when projection edge weight is null',
            );
          }
        }
      });
    }
  });
}

void _testImportedTensorParametersPreserved() {
  group('Imported tensor parameters are preserved', () {
    test('transform node keeps weight_matrix and category metadata', () {
      final projection = const canonical.CanvasProjection(
        nodes: <canonical.CanvasNode>[
          canonical.CanvasNode(
            id: 'conv_0',
            label: 'Conv2d',
            nirType: 'nir.Conv2d',
            parameters: <String, dynamic>{
              'weight_shape': <int>[1, 1, 2, 2],
              'weight_matrix': [
                [
                  [
                    [0.1, 0.2],
                    [0.3, 0.4],
                  ],
                ],
              ],
              'stride': <int>[1, 1],
            },
            metadata: <String, dynamic>{'category': 'transform'},
          ),
        ],
        edges: <canonical.CanvasEdge>[],
      );

      final result = canvasGraphFromCanonical(
        projection,
        currentGraph: _emptyGraph,
      );

      expect(result.nodes, hasLength(1));
      final node = result.nodes.first;
      expect(node.componentId, equals('nir.Conv2d'));
      expect(
        node.parameters['weight_matrix'],
        equals(const [
          [
            [
              [0.1, 0.2],
              [0.3, 0.4],
            ],
          ],
        ]),
      );
      expect(node.parameters['weight_shape'], equals(const <int>[1, 1, 2, 2]));
      expect(node.metadata['category'], equals('transform'));
    });
  });
}

// ---------------------------------------------------------------------------
// main — wire up all groups
// ---------------------------------------------------------------------------

void main() {
  _testBaselineObservation();
  _testPureLIFPreservation();
  _testEdgeCountPreservation();
  _testImportedTensorParametersPreserved();
}
