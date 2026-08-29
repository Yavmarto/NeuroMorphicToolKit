// PBT — Type Resolution Round-Trip Across All _nirTypeToComponentId Entries
//
// **Validates: Requirements 2.1, 2.4**
//
// Property 1: Bug Condition — Type Resolution Round-Trip
//
// For any list of NIR type strings drawn from the 15 keys of
// `_nirTypeToComponentId`, constructing a `CanvasProjection` with nodes
// carrying those types and calling `canvasGraphFromCanonical` must satisfy:
//
//   result.nodes[i].nirType     == inputTypes[i]
//   result.nodes[i].componentId == _nirTypeToComponentId[inputTypes[i]]
//
// This test runs on FIXED code and MUST PASS.
//
// Test structure:
//   - Enumerate all 15 NIR types individually (single-node projections)
//   - Enumerate all 15 types together in one multi-node projection
//   - Enumerate all non-trivial subsets of {nir.Input, nir.LIF, nir.Output,
//     nir.CubaLIF, nir.IF, nir.LI, nir.Linear, nir.Affine, …} to cover
//     ordering and index-accuracy simultaneously
//   - Verify positional correctness: result.nodes[i] corresponds to
//     projection.nodes[i] (no reordering)

import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical;
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart';

// ---------------------------------------------------------------------------
// The complete _nirTypeToComponentId map (mirrors design doc + source file).
// Enumerated here directly so the test is self-contained and validates every
// entry without relying on the private symbol from canvas_projection_utils.dart.
// ---------------------------------------------------------------------------

const Map<String, String> _nirTypeToComponentId = <String, String>{
  'nir.Input': 'input_node',
  'nir.Output': 'output_node',
  'nir.LIF': 'lif_population',
  'nir.CubaLIF': 'lif_population',
  'nir.IF': 'lif_population',
  'nir.LI': 'lif_population',
  'nir.Linear': 'nir.Linear',
  'nir.Affine': 'nir.Affine',
  'nir.Conv1d': 'nir.Conv1d',
  'nir.Conv2d': 'nir.Conv2d',
  'nir.Flatten': 'nir.Flatten',
  'nir.AvgPool2d': 'nir.AvgPool2d',
  'nir.SumPool2d': 'nir.SumPool2d',
  'nir.Delay': 'nir.Delay',
  'nir.Scale': 'nir.Scale',
};

// All 15 keys in declaration order — used as the canonical ordered list.
const List<String> _allNirTypes = <String>[
  'nir.Input',
  'nir.Output',
  'nir.LIF',
  'nir.CubaLIF',
  'nir.IF',
  'nir.LI',
  'nir.Linear',
  'nir.Affine',
  'nir.Conv1d',
  'nir.Conv2d',
  'nir.Flatten',
  'nir.AvgPool2d',
  'nir.SumPool2d',
  'nir.Delay',
  'nir.Scale',
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Empty [CanvasGraph] used as the baseline current graph — no prior positions.
CanvasGraph get _emptyGraph => CanvasGraph(
  nodes: const <CanvasNode>[],
  edges: const <CanvasEdge>[],
  metadata: const <String, dynamic>{},
);

/// Build a [canonical.CanvasProjection] whose nodes carry exactly [nirTypes]
/// in order.
canonical.CanvasProjection _projectionFromTypes(List<String> nirTypes) {
  return canonical.CanvasProjection(
    nodes: <canonical.CanvasNode>[
      for (var i = 0; i < nirTypes.length; i++)
        canonical.CanvasNode(
          id: 'node_$i',
          label: nirTypes[i],
          nirType: nirTypes[i],
        ),
    ],
    edges: const <canonical.CanvasEdge>[],
  );
}

/// Assert the round-trip property for a projection built from [nirTypes]:
///   result.nodes[i].nirType     == nirTypes[i]
///   result.nodes[i].componentId == _nirTypeToComponentId[nirTypes[i]]
void _assertRoundTrip(List<String> nirTypes) {
  final projection = _projectionFromTypes(nirTypes);
  final result = canvasGraphFromCanonical(
    projection,
    currentGraph: _emptyGraph,
  );

  expect(
    result.nodes,
    hasLength(nirTypes.length),
    reason: 'Node count must equal input type count (${nirTypes.length})',
  );

  for (var i = 0; i < nirTypes.length; i++) {
    final inputType = nirTypes[i];
    final expectedComponentId = _nirTypeToComponentId[inputType]!;
    final node = result.nodes[i];

    expect(
      node.nirType,
      equals(inputType),
      reason:
          'Property 1 — nodes[$i]: nirType round-trip failed. '
          "Input='$inputType', got='${node.nirType}'. "
          'canvasGraphFromCanonical must preserve nirType from the projection node.',
    );

    expect(
      node.componentId,
      equals(expectedComponentId),
      reason:
          'Property 1 — nodes[$i]: componentId lookup failed. '
          "Input='$inputType', expected componentId='$expectedComponentId', "
          "got='${node.componentId}'. "
          'canvasGraphFromCanonical must resolve componentId via _nirTypeToComponentId.',
    );
  }
}

// ---------------------------------------------------------------------------
// Combinatorial subset helpers
// ---------------------------------------------------------------------------

/// Generate all length-2 ordered pairs from [items].
Iterable<List<T>> _pairs<T>(List<T> items) sync* {
  for (var i = 0; i < items.length; i++) {
    for (var j = 0; j < items.length; j++) {
      if (i != j) yield <T>[items[i], items[j]];
    }
  }
}

/// Generate all length-3 ordered triples from [items].
Iterable<List<T>> _triples<T>(List<T> items) sync* {
  for (var i = 0; i < items.length; i++) {
    for (var j = 0; j < items.length; j++) {
      for (var k = 0; k < items.length; k++) {
        if (i != j && j != k && i != k) yield <T>[items[i], items[j], items[k]];
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── Property 1 / Single-node exhaustive coverage ─────────────────────────
  //
  // For each of the 15 NIR types, build a single-node projection and assert
  // the round-trip holds.  This gives one failing counterexample per type if
  // the map entry is wrong.
  //
  // **Validates: Requirements 2.1, 2.4**
  group(
    'Property 1 — Single-node round-trip: '
    'all 15 nirTypeToComponentId entries preserve nirType and componentId',
    () {
      for (final nirType in _allNirTypes) {
        final expectedCid = _nirTypeToComponentId[nirType]!;
        test(
          "nirType='$nirType' → componentId='$expectedCid'",
          () => _assertRoundTrip(<String>[nirType]),
        );
      }
    },
  );

  // ── Property 1 / All-types multi-node projection ──────────────────────────
  //
  // Build a single 15-node projection containing one node per NIR type in
  // declaration order. Assert that every node at index i carries the correct
  // nirType and componentId — verifying positional correctness (no off-by-one
  // or node-reordering introduced by canvasGraphFromCanonical).
  //
  // **Validates: Requirements 2.1, 2.4**
  group('Property 1 — All-15-types multi-node projection: '
      'each node index is resolved independently and correctly', () {
    test(
      'projection with all 15 NIR types in order: '
      'every result.nodes[i] has correct nirType and componentId',
      () => _assertRoundTrip(_allNirTypes),
    );
  });

  // ── Property 1 / Reversed order ───────────────────────────────────────────
  //
  // Run the all-15 round-trip with the type list reversed to confirm that
  // index-based resolution is independent of declaration order.
  group('Property 1 — All-15-types reversed order: '
      'index resolution is order-independent', () {
    test(
      'projection with all 15 NIR types in reversed order: '
      'every result.nodes[i] has correct nirType and componentId',
      () => _assertRoundTrip(_allNirTypes.reversed.toList()),
    );
  });

  // ── Property 1 / Pairwise combinations ────────────────────────────────────
  //
  // For each ordered pair drawn from a representative subset of 8 types (the
  // full 15×14 = 210 pairs would produce 210 tests; we use 8 to keep the suite
  // fast while still covering every type at least once in a multi-node context).
  //
  // **Validates: Requirements 2.1, 2.4**
  group('Property 1 — Pairwise combinations: '
      'two-node projections preserve both nirTypes independently', () {
    // Representative subset: all structurally distinct component-id mappings
    // are present (input_node, output_node, lif_population, plus several
    // identity-mapped pass-through types).
    const representativeTypes = <String>[
      'nir.Input',
      'nir.Output',
      'nir.LIF',
      'nir.CubaLIF',
      'nir.Linear',
      'nir.Conv1d',
      'nir.Delay',
      'nir.Scale',
    ];

    for (final pair in _pairs(representativeTypes)) {
      test(
        'pair [${pair[0]}, ${pair[1]}]: both nodes round-trip correctly',
        () => _assertRoundTrip(pair),
      );
    }
  });

  // ── Property 1 / Triple combinations ─────────────────────────────────────
  //
  // For each ordered triple drawn from the same representative subset.  Covers
  // scenarios where mixed-type nodes appear before and after each other, ensuring
  // the loop index is not accidentally reused or skipped.
  group('Property 1 — Triple combinations: '
      'three-node projections preserve all three nirTypes independently', () {
    // Smaller subset for triples to keep test count manageable
    // (~5×4×3 = 60 triples).
    const tripleTypes = <String>[
      'nir.Input',
      'nir.LIF',
      'nir.Output',
      'nir.CubaLIF',
      'nir.Linear',
    ];

    for (final triple in _triples(tripleTypes)) {
      test(
        'triple [${triple[0]}, ${triple[1]}, ${triple[2]}]: '
        'all three nodes round-trip correctly',
        () => _assertRoundTrip(triple),
      );
    }
  });

  // ── Property 1 / Repeated types ───────────────────────────────────────────
  //
  // Multiple nodes of the same NIR type in a single projection — confirms that
  // the loop iterates over every node independently and doesn't short-circuit
  // after the first occurrence.
  group('Property 1 — Repeated types: '
      'multiple nodes with the same NIR type all resolve correctly', () {
    const repeatedCases = <(String, int)>[
      ('nir.LIF', 5),
      ('nir.Input', 3),
      ('nir.Output', 3),
      ('nir.CubaLIF', 4),
      ('nir.Linear', 3),
    ];

    for (final (nirType, count) in repeatedCases) {
      test(
        "type='$nirType' repeated $count times: all $count nodes round-trip correctly",
        () => _assertRoundTrip(List<String>.filled(count, nirType)),
      );
    }
  });

  // ── Property 1 / Null-fallback types coexisting with known types ──────────
  //
  // A projection where some nodes have null nirType (pre-fix backend nodes that
  // fall back to 'nir.LIF') interleaved with known-type nodes. This validates
  // that the fallback path does not contaminate the explicit-type path.
  group(
    'Property 1 — Null-fallback coexistence: '
    'explicit nirType nodes are unaffected by adjacent null-nirType nodes',
    () {
      test(
        'projection [nir.Input, null, nir.Output]: '
        "null node gets nirType='nir.LIF', explicit nodes are unaffected",
        () {
          final projection = const canonical.CanvasProjection(
            nodes: <canonical.CanvasNode>[
              canonical.CanvasNode(
                id: 'node_0',
                label: 'Input',
                nirType: 'nir.Input',
              ),
              canonical.CanvasNode(
                id: 'node_1',
                label: 'LIF',
              ), // nirType == null
              canonical.CanvasNode(
                id: 'node_2',
                label: 'Output',
                nirType: 'nir.Output',
              ),
            ],
            edges: <canonical.CanvasEdge>[],
          );

          final result = canvasGraphFromCanonical(
            projection,
            currentGraph: _emptyGraph,
          );

          expect(result.nodes, hasLength(3));

          // node_0: explicit nir.Input
          expect(
            result.nodes[0].nirType,
            equals('nir.Input'),
            reason: 'node_0: nirType must be nir.Input (explicit)',
          );
          expect(
            result.nodes[0].componentId,
            equals('input_node'),
            reason: 'node_0: componentId must be input_node',
          );

          // node_1: null → falls back to nir.LIF
          expect(
            result.nodes[1].nirType,
            equals('nir.LIF'),
            reason: 'node_1: null nirType must fall back to nir.LIF',
          );
          expect(
            result.nodes[1].componentId,
            equals('lif_population'),
            reason: 'node_1: null nirType must fall back to lif_population',
          );

          // node_2: explicit nir.Output
          expect(
            result.nodes[2].nirType,
            equals('nir.Output'),
            reason: 'node_2: nirType must be nir.Output (explicit)',
          );
          expect(
            result.nodes[2].componentId,
            equals('output_node'),
            reason: 'node_2: componentId must be output_node',
          );
        },
      );

      test(
        'projection [null, nir.Linear, null, nir.Scale, null]: '
        'null nodes get lif_population; explicit nodes use identity mapping',
        () {
          final projection = const canonical.CanvasProjection(
            nodes: <canonical.CanvasNode>[
              canonical.CanvasNode(id: 'node_0', label: 'N0'), // null
              canonical.CanvasNode(
                id: 'node_1',
                label: 'N1',
                nirType: 'nir.Linear',
              ),
              canonical.CanvasNode(id: 'node_2', label: 'N2'), // null
              canonical.CanvasNode(
                id: 'node_3',
                label: 'N3',
                nirType: 'nir.Scale',
              ),
              canonical.CanvasNode(id: 'node_4', label: 'N4'), // null
            ],
            edges: <canonical.CanvasEdge>[],
          );

          final result = canvasGraphFromCanonical(
            projection,
            currentGraph: _emptyGraph,
          );

          expect(result.nodes, hasLength(5));

          expect(result.nodes[0].nirType, equals('nir.LIF'));
          expect(result.nodes[0].componentId, equals('lif_population'));

          expect(result.nodes[1].nirType, equals('nir.Linear'));
          expect(result.nodes[1].componentId, equals('nir.Linear'));

          expect(result.nodes[2].nirType, equals('nir.LIF'));
          expect(result.nodes[2].componentId, equals('lif_population'));

          expect(result.nodes[3].nirType, equals('nir.Scale'));
          expect(result.nodes[3].componentId, equals('nir.Scale'));

          expect(result.nodes[4].nirType, equals('nir.LIF'));
          expect(result.nodes[4].componentId, equals('lif_population'));
        },
      );
    },
  );

  // ── Property 1 / Identity-mapped types (pass-through componentId) ─────────
  //
  // nir.Linear, nir.Affine, nir.Conv1d, nir.Conv2d, nir.Flatten,
  // nir.AvgPool2d, nir.SumPool2d, nir.Delay, nir.Scale all map their nirType
  // string to itself as the componentId.  Test them together to confirm the
  // identity mapping is correct for each.
  group('Property 1 — Identity-mapped types: '
      'componentId == nirType for pass-through entries', () {
    const identityMappedTypes = <String>[
      'nir.Linear',
      'nir.Affine',
      'nir.Conv1d',
      'nir.Conv2d',
      'nir.Flatten',
      'nir.AvgPool2d',
      'nir.SumPool2d',
      'nir.Delay',
      'nir.Scale',
    ];

    test('projection with all 9 identity-mapped types: '
        'componentId == nirType for each node', () {
      final projection = _projectionFromTypes(identityMappedTypes);
      final result = canvasGraphFromCanonical(
        projection,
        currentGraph: _emptyGraph,
      );

      expect(result.nodes, hasLength(identityMappedTypes.length));

      for (var i = 0; i < identityMappedTypes.length; i++) {
        final nirType = identityMappedTypes[i];
        expect(
          result.nodes[i].nirType,
          equals(nirType),
          reason: 'Identity-mapped type[$i]: nirType must equal input $nirType',
        );
        expect(
          result.nodes[i].componentId,
          equals(nirType),
          reason:
              'Identity-mapped type[$i]: componentId must equal nirType '
              '(identity mapping) for $nirType',
        );
      }
    });
  });

  // ── Property 1 / LIF-family types all map to lif_population ───────────────
  //
  // nir.LIF, nir.CubaLIF, nir.IF, nir.LI all resolve to 'lif_population'.
  group('Property 1 — LIF-family componentId: '
      'nir.LIF, nir.CubaLIF, nir.IF, nir.LI all map to lif_population', () {
    const lifFamilyTypes = <String>[
      'nir.LIF',
      'nir.CubaLIF',
      'nir.IF',
      'nir.LI',
    ];

    test(
      'projection with all 4 LIF-family types: all componentIds == lif_population',
      () {
        final projection = _projectionFromTypes(lifFamilyTypes);
        final result = canvasGraphFromCanonical(
          projection,
          currentGraph: _emptyGraph,
        );

        expect(result.nodes, hasLength(lifFamilyTypes.length));

        for (var i = 0; i < lifFamilyTypes.length; i++) {
          expect(
            result.nodes[i].nirType,
            equals(lifFamilyTypes[i]),
            reason:
                'LIF-family[$i]: nirType must equal input ${lifFamilyTypes[i]}',
          );
          expect(
            result.nodes[i].componentId,
            equals('lif_population'),
            reason:
                'LIF-family[$i]: componentId must be lif_population '
                'for ${lifFamilyTypes[i]}',
          );
        }
      },
    );
  });
}
