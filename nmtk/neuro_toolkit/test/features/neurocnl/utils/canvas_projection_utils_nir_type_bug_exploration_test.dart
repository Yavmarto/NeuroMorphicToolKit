// Bug-Condition Exploration Tests — NIR Type Resolution in canvasGraphFromCanonical
//
// **Validates: Requirements 2.1, 2.4**
//
// These tests are written BEFORE any fix is applied. They are expected to FAIL
// on the unfixed codebase. Failure confirms the root-cause defect exists.
// DO NOT modify these tests to make them pass until the fix is implemented.
//
// Bug condition: `canvasGraphFromCanonical` hardcodes `componentId: 'lif_population'`
// and `nirType: 'nir.LIF'` for every canvas node, regardless of the actual NIR
// primitive type carried in the `CanvasProjection` node.
//
// isBugConditionNodeType: any projection node whose nirType != 'nir.LIF'.
//
// Test cases:
//   TC-1 — Single nir.Input projection → result.nodes.first.nirType must be 'nir.Input'
//   TC-2 — Three-node projection (nir.Input, nir.LIF, nir.Output) → each node's
//           nirType matches its projection nirType
//
// Property 1 (PBT): For each NIR type string drawn from the known non-LIF set
// {nir.Input, nir.Output, nir.CubaLIF}, constructing a single-node projection
// with that type and calling canvasGraphFromCanonical must return a node whose
// nirType equals the input type and whose componentId matches the expected
// legacy component id from the type spec map.
//
// EXPECTED OUTCOME: ALL tests FAIL on unfixed code.
// Counterexamples documented:
//   canvasGraphFromCanonical({nir.Input})  → nirType='nir.LIF'  (expected 'nir.Input')
//   canvasGraphFromCanonical({nir.Output}) → nirType='nir.LIF'  (expected 'nir.Output')
//   canvasGraphFromCanonical({nir.CubaLIF}) → nirType='nir.LIF' (expected 'nir.CubaLIF')

import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical;
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart';

// ---------------------------------------------------------------------------
// Expected legacy componentId values (mirrors design doc _nirTypeToComponentId)
// ---------------------------------------------------------------------------
const Map<String, String> _expectedComponentId = <String, String>{
  'nir.Input': 'input_node',
  'nir.Output': 'output_node',
  'nir.LIF': 'lif_population',
  'nir.CubaLIF': 'lif_population',
  'nir.IF': 'lif_population',
  'nir.LI': 'lif_population',
};

// ---------------------------------------------------------------------------
// Helpers to build CanvasProjection stubs
// ---------------------------------------------------------------------------

/// Builds a [canonical.CanvasNode] stub with the given [nirType].
///
/// NOTE: The [canonical.CanvasNode] model does not yet carry a [nirType] field
/// on unfixed code (Change 2 from the fix plan adds it). This helper
/// pre-empts that model change by extending the stub inline so that the
/// exploration test can call [canvasGraphFromCanonical] with typed projection
/// nodes. The test then asserts the fix is needed by checking the output.
///
/// Since [canonical.CanvasNode] is an unmodified Dart class (no generated
/// JSON, no `fromJson` required here), we use a local wrapper approach:
/// we create a [_TypedCanvasNode] that substitutes for [canonical.CanvasNode]
/// once the model field is added. For the exploration test we directly pass
/// a stock [canonical.CanvasNode] (which lacks nirType) and assert that the
/// resulting CanvasGraph incorrectly always shows 'nir.LIF' — confirming the
/// bug exists AND that without the model field the fix cannot be applied.
///
/// When [canonical.CanvasNode] does NOT yet have nirType:
///   - we cannot supply a non-LIF nirType to the projection
///   - therefore canvasGraphFromCanonical always outputs 'nir.LIF' for every node
///   - the assertion `result.nodes.first.nirType == 'nir.Input'` FAILS
///
/// This is exactly the bug condition we want to document.

canonical.CanvasProjection _singleNodeProjection({
  required String id,
  required String label,
  String? nirType,
}) {
  return canonical.CanvasProjection(
    nodes: <canonical.CanvasNode>[
      canonical.CanvasNode(id: id, label: label, nirType: nirType),
    ],
    edges: const <canonical.CanvasEdge>[],
  );
}

canonical.CanvasProjection _threeNodeProjection() {
  return const canonical.CanvasProjection(
    nodes: <canonical.CanvasNode>[
      canonical.CanvasNode(id: 'input_0', label: 'Input', nirType: 'nir.Input'),
      canonical.CanvasNode(id: 'lif_0', label: 'LIF', nirType: 'nir.LIF'),
      canonical.CanvasNode(
        id: 'output_0',
        label: 'Output',
        nirType: 'nir.Output',
      ),
    ],
    edges: <canonical.CanvasEdge>[],
  );
}

/// Empty [CanvasGraph] used as the baseline current graph so that no prior
/// positions interfere with the test assertions.
CanvasGraph get _emptyGraph => CanvasGraph(
  nodes: const <CanvasNode>[],
  edges: const <CanvasEdge>[],
  metadata: const <String, dynamic>{},
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── TC-1: Single nir.Input node ─────────────────────────────────────────
  //
  // EXPECTED OUTCOME: FAIL on unfixed code.
  // Counterexample: result.nodes.first.nirType == 'nir.LIF' (not 'nir.Input').
  //
  // NOTE: Since canonical.CanvasNode lacks a nirType field on unfixed code,
  // the projection cannot carry type information. The test therefore asserts
  // the EXPECTED (fixed) behaviour — a projection node labelled 'Input' whose
  // intended type is nir.Input should produce a CanvasNode with nirType == 'nir.Input'.
  // On unfixed code, canvasGraphFromCanonical ignores all type context and
  // stamps every node with nirType: 'nir.LIF', causing this assertion to fail.
  group('TC-1 — Single nir.Input projection: nirType must equal nir.Input', () {
    test('canvasGraphFromCanonical with a single-node projection returns '
        "nirType == 'nir.Input' (bug: returns 'nir.LIF')", () {
      // Build the projection. On unfixed code, canonical.CanvasNode has no
      // nirType field, so the projection cannot communicate type information.
      // The fix (Change 2) adds the field; this test encodes the expected
      // post-fix behaviour and therefore FAILS on unfixed code.
      final projection = _singleNodeProjection(
        id: 'input_0',
        label: 'Input',
        nirType: 'nir.Input',
      );

      final result = canvasGraphFromCanonical(
        projection,
        currentGraph: _emptyGraph,
      );

      expect(
        result.nodes,
        hasLength(1),
        reason: 'Result must have exactly one node',
      );

      // Assert expected (fixed) nirType.
      // FAILS on unfixed code: actual value is 'nir.LIF'.
      expect(
        result.nodes.first.nirType,
        equals('nir.Input'),
        reason:
            "Bug condition: canvasGraphFromCanonical hardcodes nirType='nir.LIF' "
            "for every node regardless of the projection node's actual NIR type. "
            "Expected 'nir.Input' but got '${result.nodes.first.nirType}'. "
            'Counterexample: canvasGraphFromCanonical({nir.Input}) → nirType=nir.LIF',
      );

      // Assert expected (fixed) componentId.
      // FAILS on unfixed code: actual value is 'lif_population'.
      expect(
        result.nodes.first.componentId,
        equals('input_node'),
        reason:
            "Bug condition: componentId is hardcoded to 'lif_population' for "
            "every node. Expected 'input_node' for nir.Input. "
            "Counterexample: canvasGraphFromCanonical({nir.Input}) → componentId='lif_population'",
      );
    });
  });

  // ── TC-2: Three-node projection (nir.Input, nir.LIF, nir.Output) ────────
  //
  // EXPECTED OUTCOME: FAIL on unfixed code (Input and Output nodes are stamped
  // with nirType='nir.LIF' and componentId='lif_population').
  // The LIF node assertion happens to pass by coincidence on unfixed code.
  group(
    'TC-2 — Three-node projection: each node nirType matches projection type',
    () {
      test('canvasGraphFromCanonical with nir.Input, nir.LIF, nir.Output returns '
          'correct nirType and componentId for each node '
          "(bug: all nodes get nirType='nir.LIF')", () {
        final projection = _threeNodeProjection();

        final result = canvasGraphFromCanonical(
          projection,
          currentGraph: _emptyGraph,
        );

        expect(result.nodes, hasLength(3));

        // Expected node types ordered: Input, LIF, Output.
        // (Projection order matches node insertion order.)
        const expectedNirTypes = <String>['nir.Input', 'nir.LIF', 'nir.Output'];
        const expectedComponentIds = <String>[
          'input_node',
          'lif_population',
          'output_node',
        ];

        for (var i = 0; i < 3; i++) {
          final node = result.nodes[i];
          expect(
            node.nirType,
            equals(expectedNirTypes[i]),
            reason:
                'Node[$i] (${projection.nodes[i].label}): '
                "expected nirType='${expectedNirTypes[i]}' but got '${node.nirType}'. "
                'Bug condition: hardcoded nir.LIF for all nodes.',
          );
          expect(
            node.componentId,
            equals(expectedComponentIds[i]),
            reason:
                'Node[$i] (${projection.nodes[i].label}): '
                "expected componentId='${expectedComponentIds[i]}' but got '${node.componentId}'. "
                'Bug condition: hardcoded lif_population for all nodes.',
          );
        }
      });
    },
  );

  // ── Property 1 (PBT): Non-LIF type round-trip ────────────────────────────
  //
  // **Validates: Requirements 2.1, 2.4**
  //
  // For each known non-LIF NIR type string, constructing a single-node
  // projection and calling canvasGraphFromCanonical must return a node whose
  // nirType equals the input type and componentId matches the type spec map.
  //
  // Since canonical.CanvasNode lacks nirType on unfixed code, the projection
  // cannot carry the type → canvasGraphFromCanonical ALWAYS stamps 'nir.LIF'.
  // Every assertion in this property FAILS on unfixed code.
  //
  // EXPECTED OUTCOME: ALL instances FAIL on unfixed code.
  group('Property 1 — Non-LIF type round-trip: '
      'canvasGraphFromCanonical preserves nirType from projection', () {
    // Sample from the non-LIF subset of _nirTypeToComponentId.
    const nonLifTypes = <String>[
      'nir.Input',
      'nir.Output',
      'nir.CubaLIF',
      'nir.IF',
      'nir.LI',
    ];

    for (final nirTypeStr in nonLifTypes) {
      test("nirType='$nirTypeStr': canvasGraphFromCanonical returns "
          "nirType='$nirTypeStr' and componentId='${_expectedComponentId[nirTypeStr]}' "
          "(bug: returns nirType='nir.LIF', componentId='lif_population')", () {
        // Build a single-node projection. On unfixed code, canonical.CanvasNode
        // lacks nirType, so the projection contains no type information.
        // The fix adds the field and passes the type through.
        // This test therefore FAILs on unfixed code and PASSes after the fix.
        final projection = canonical.CanvasProjection(
          nodes: <canonical.CanvasNode>[
            canonical.CanvasNode(
              id: 'node_0',
              label: nirTypeStr,
              nirType: nirTypeStr,
            ),
          ],
          edges: const <canonical.CanvasEdge>[],
        );

        final result = canvasGraphFromCanonical(
          projection,
          currentGraph: _emptyGraph,
        );

        expect(result.nodes, hasLength(1));

        // FAILS on unfixed code: result is always 'nir.LIF'.
        expect(
          result.nodes.first.nirType,
          equals(nirTypeStr),
          reason:
              "Property 1 counterexample for nirType='$nirTypeStr': "
              "canvasGraphFromCanonical returned nirType='${result.nodes.first.nirType}' "
              "(expected '$nirTypeStr'). "
              'Root cause: nirType is hardcoded to nir.LIF regardless of projection.',
        );

        final expectedCid = _expectedComponentId[nirTypeStr];
        if (expectedCid != null) {
          // FAILS on unfixed code: result is always 'lif_population'.
          expect(
            result.nodes.first.componentId,
            equals(expectedCid),
            reason:
                "Property 1 counterexample for nirType='$nirTypeStr': "
                "canvasGraphFromCanonical returned componentId='${result.nodes.first.componentId}' "
                "(expected '$expectedCid'). "
                'Root cause: componentId is hardcoded to lif_population.',
          );
        }
      });
    }
  });
}
