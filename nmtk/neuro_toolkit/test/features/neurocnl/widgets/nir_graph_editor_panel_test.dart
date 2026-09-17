import 'package:riverpod_annotation/riverpod_annotation.dart';
// Widget Tests — _NirGraphEditorPanel: NIR viewer column absent (Property 1 sub-check)
//
// **Validates: Requirements 2.6**
//
// Task 5.2: Verify NIR viewer column is absent from _NirGraphEditorPanel after
// the fix applied in task 5.1.
//
// Tests:
//   T1 — No HDF5 tree-view text present when _NirGraphEditorPanel is rendered
//        with a populated canvas graph (confirms the _NirTreeView / Row column
//        has been removed).
//   T2 — _NirNodeCard widgets are rendered for each canvas node (node count matches).
//   T3 — _NirEdgeList "Connections" header is present when graph has edges.
//   T4 — Empty graph shows the empty-state placeholder, not a tree view.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_hdf5_tree.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/nir_import_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_view_mode_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/nir_importer_tab.dart';

// ---------------------------------------------------------------------------
// Fake canvas API client — avoids network calls
// ---------------------------------------------------------------------------

class _FakeCanvasApiClient extends ApiClient {
  _FakeCanvasApiClient() : super(baseUrl: 'http://localhost:0');

  @override
  Future<String> generateCnl(CanvasGraph graph) async => '';

  @override
  Future<CanvasGraph> repairCnl(String cnl, {CanvasGraph? graph}) async =>
      graph ??
      CanvasGraph(nodes: const [], edges: const [], metadata: const {});

  @override
  Future<ImportNirBytesResponse> importNirBytes(Uint8List payload) async =>
      ImportNirBytesResponse(
        graph: CanvasGraph(
          nodes: const [],
          edges: const [],
          metadata: const {},
        ),
      );

  @override
  Future<Uint8List> exportNirBytes(CanvasGraph graph) async => Uint8List(0);

  @override
  Future<String> generateCnlFromNirBytes(Uint8List payload) async => '';
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A minimal loaded [NirInspectResult] with no children.
NirInspectResult _stubInspectResult() => const NirInspectResult(
  fileName: 'test.nir',
  fileSizeBytes: 128,
  root: NirHdf5Group(name: '/', attrs: {}, children: []),
);

/// Creates a [CanvasNode] with the given [id] and optional [nirType].
CanvasNode _makeNode(String id, {String nirType = 'nir.LIF'}) => CanvasNode(
  id: id,
  componentId: 'lif_population',
  nirType: nirType,
  label: 'Node $id',
  parameters: <String, dynamic>{
    'name': id,
    'n_neurons': 10,
    'threshold': 1.0,
    'tau': 0.02,
  },
  position: const <double>[100.0, 100.0],
);

/// Builds a [ProviderContainer] seeded with the given [graph] and a
/// [NirImportState] in loaded/canvas status so [_LoadedView] renders.
ProviderContainer _makeContainer({required CanvasGraph graph}) {
  final container = ProviderContainer(
    overrides: <Override>[
      canvas_sync.apiClientProvider.overrideWithValue(_FakeCanvasApiClient()),
    ],
  );

  container.read(studioViewModeProvider.notifier).setMode(StudioViewMode.nir);
  container.read(canvasProvider.notifier).setGraph(graph);
  container.read(nirImportProvider.notifier).state = NirImportState.loaded(
    source: NirSource.canvas,
    result: _stubInspectResult(),
    writeBackConsumed: true,
  );
  container.read(specTextProvider.notifier).set('');

  return container;
}

/// Wraps [NirImporterTab] in a full [MaterialApp] using [UncontrolledProviderScope].
Widget _buildApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 900, height: 700, child: NirImporterTab()),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
  });

  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
  });

  // ── T1 — NIR tree-view column is absent ──────────────────────────────────
  //
  // Validates Requirement 2.6 / Property 6:
  //   After the fix in task 5.1, _NirGraphEditorPanel must NOT render any
  //   HDF5 tree-view widget (the Expanded(flex:2) column was removed).
  //
  // Since _NirTreeView was deleted from the source, we verify its absence
  // by confirming that the widget tree contains no VerticalDivider (which
  // was the separator between the two columns) and no tree-view group-tile
  // text markers. We also confirm the panel is a single-column ListView,
  // not a Row with multiple Expanded children.
  group('T1 — NIR viewer column is absent', () {
    testWidgets(
      '_NirGraphEditorPanel with a populated graph contains no VerticalDivider '
      '(confirms the two-column Row layout was removed)',
      (WidgetTester tester) async {
        final graph = CanvasGraph(
          nodes: [_makeNode('input_1', nirType: 'nir.Input')],
          edges: const [],
          metadata: const {},
        );

        final container = _makeContainer(graph: graph);
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildApp(container));
        await tester.pumpAndSettle();

        // The VerticalDivider was the visual separator between the old
        // tree-view column and the node-editor column. Its absence confirms
        // the two-column Row was removed.
        expect(
          find.byType(VerticalDivider),
          findsNothing,
          reason:
              'T1: VerticalDivider must not be present — the two-column Row '
              'layout containing _NirTreeView has been removed.',
        );
      },
    );

    testWidgets(
      '_NirGraphEditorPanel with a populated graph renders a ListView '
      '(single-column layout, not a Row with multiple Expanded children)',
      (WidgetTester tester) async {
        final graph = CanvasGraph(
          nodes: [
            _makeNode('lif_1'),
            _makeNode('input_1', nirType: 'nir.Input'),
          ],
          edges: const [],
          metadata: const {},
        );

        final container = _makeContainer(graph: graph);
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildApp(container));
        await tester.pumpAndSettle();

        // Fixed layout: _NirGraphEditorPanel returns a ListView directly,
        // not a Row. Confirm a ListView is present inside the panel area.
        expect(
          find.byType(ListView),
          findsAtLeastNWidgets(1),
          reason:
              'T1b: _NirGraphEditorPanel must use a ListView (single column) '
              'rather than a Row with multiple Expanded children.',
        );
      },
    );
  });

  // ── T2 — _NirNodeCard count matches graph node count ─────────────────────
  //
  // Validates Requirement 2.6 / Property 9:
  //   After removing the tree-view column, the node/edge editor must still
  //   render one node card per canvas node.
  group('T2 — _NirNodeCard count matches graph node count', () {
    testWidgets('renders exactly 1 node card for a single-node graph', (
      WidgetTester tester,
    ) async {
      final graph = CanvasGraph(
        nodes: [_makeNode('lif_1')],
        edges: const [],
        metadata: const {},
      );

      final container = _makeContainer(graph: graph);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      // Each node card has an ExpansionTile titled with the node's label.
      expect(
        find.text('Node lif_1'),
        findsOneWidget,
        reason: 'T2: exactly 1 node card must render for a single-node graph.',
      );
    });

    testWidgets('renders exactly 3 node cards for a three-node graph', (
      WidgetTester tester,
    ) async {
      final graph = CanvasGraph(
        nodes: [
          _makeNode('input_1', nirType: 'nir.Input'),
          _makeNode('lif_1', nirType: 'nir.LIF'),
          _makeNode('output_1', nirType: 'nir.Output'),
        ],
        edges: const [],
        metadata: const {},
      );

      final container = _makeContainer(graph: graph);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      // Verify all three node labels appear.
      expect(
        find.text('Node input_1'),
        findsOneWidget,
        reason: 'T2: node card for input_1 must be rendered.',
      );
      expect(
        find.text('Node lif_1'),
        findsOneWidget,
        reason: 'T2: node card for lif_1 must be rendered.',
      );
      expect(
        find.text('Node output_1'),
        findsOneWidget,
        reason: 'T2: node card for output_1 must be rendered.',
      );

      // Three delete buttons confirm three node cards.
      expect(
        find.byTooltip('Delete node'),
        findsNWidgets(3),
        reason:
            'T2: exactly 3 "Delete node" buttons must appear for a '
            'three-node graph, one per node card.',
      );
    });

    testWidgets('renders exactly 2 node cards for a two-node graph', (
      WidgetTester tester,
    ) async {
      final graph = CanvasGraph(
        nodes: [_makeNode('node_a'), _makeNode('node_b')],
        edges: const [],
        metadata: const {},
      );

      final container = _makeContainer(graph: graph);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      expect(
        find.byTooltip('Delete node'),
        findsNWidgets(2),
        reason:
            'T2: exactly 2 "Delete node" buttons must appear for a '
            'two-node graph.',
      );
    });
  });

  // ── T3 — _NirEdgeList "Connections" present when edges exist ─────────────
  //
  // Validates Requirement 2.6 / Property 9:
  //   The edge list widget must continue to render after the column removal.
  group('T3 — _NirEdgeList renders Connections section', () {
    testWidgets('"Connections" header is present when the graph has one edge', (
      WidgetTester tester,
    ) async {
      final graph = CanvasGraph(
        nodes: [_makeNode('node_a'), _makeNode('node_b')],
        edges: [
          CanvasEdge(
            id: 'edge_a_b',
            sourceNodeId: 'node_a',
            sourcePort: 'out',
            targetNodeId: 'node_b',
            targetPort: 'in',
            parameters: const <String, dynamic>{'weight': 1.0},
          ),
        ],
        metadata: const {},
      );

      final container = _makeContainer(graph: graph);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      expect(
        find.text('Connections'),
        findsOneWidget,
        reason:
            'T3: "Connections" section header must be present when the graph '
            'has at least one edge.',
      );
    });
  });

  // ── T4 — Empty graph shows empty-state placeholder ───────────────────────
  //
  // Validates Requirement 2.6 / Property 9:
  //   An empty canvas graph must show the _EmptyGraphEditor placeholder,
  //   not any tree-view widget.
  group('T4 — Empty graph shows placeholder', () {
    testWidgets('renders empty-state text when canvas graph has no nodes', (
      WidgetTester tester,
    ) async {
      final graph = CanvasGraph(
        nodes: const [],
        edges: const [],
        metadata: const {},
      );

      final container = _makeContainer(graph: graph);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      expect(
        find.text('No editable NIR graph nodes.'),
        findsOneWidget,
        reason:
            'T4: empty graph must show the _EmptyGraphEditor placeholder text.',
      );

      // No node cards should be present.
      expect(
        find.byTooltip('Delete node'),
        findsNothing,
        reason: 'T4: no node cards must render for an empty graph.',
      );

      // No VerticalDivider (tree-view column absent even for empty graphs).
      expect(
        find.byType(VerticalDivider),
        findsNothing,
        reason:
            'T4: VerticalDivider must not be present even when the graph is empty.',
      );
    });
  });
}
