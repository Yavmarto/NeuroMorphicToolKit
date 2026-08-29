import 'package:riverpod_annotation/riverpod_annotation.dart';
// Regression test for zeta-theming-migration Wave 3a (Task 5.3):
// the NIR Inspector subtree (NirImporterTab) must contain no
// NmtkSurfaceCard / NeurocnlSectionCard whose subtree contains another
// NmtkSurfaceCard / NeurocnlSectionCard, and must contain no decorated
// Container/Ink with both BoxDecoration.color and BoxDecoration.borderRadius
// inside any NmtkSurfaceCard ancestor.
//
// Discovery for Task 4.2 confirmed that nir_importer_tab.dart has no
// NmtkSurfaceCard / NeurocnlSectionCard / ZetaCard ancestor anywhere in
// its widget tree — the inner Material `Card`s (_NirNodeCard, _NirEdgeList)
// are flat siblings inside a ListView, not card-nested. The audit screenshot
// is stale on this finding. This test locks the structural invariant so
// future edits cannot reintroduce a nested-card pattern.
//
// Validates: Requirements 5.1, 5.2, 5.5, 5.6, 9.6.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
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
// Fake canvas API client — avoids network calls during widget pumping
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

/// A minimal loaded [NirInspectResult] with no children — sufficient to drive
/// the [_LoadedView] / [_NirGraphEditorPanel] code path so the per-node /
/// per-edge `Card` siblings render and can be inspected for card nesting.
NirInspectResult _stubInspectResult() => const NirInspectResult(
  fileName: 'test.nir',
  fileSizeBytes: 128,
  root: NirHdf5Group(name: '/', attrs: {}, children: []),
);

/// Creates a [CanvasNode] with the given [id]. Two nodes plus one edge is
/// enough to render both `_NirNodeCard` siblings and the `_NirEdgeList`
/// `Card` so the structural assertions cover every card-rendering branch
/// inside the loaded view.
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

/// Builds a [ProviderContainer] seeded so [NirImporterTab] renders the
/// requested `NirImportStatus`.
///
/// When [graph] is non-null the container is seeded with a loaded NIR
/// import state so [_LoadedView] / [_NirGraphEditorPanel] render. When
/// [graph] is null the container is left at the default idle state so
/// [_IdlePlaceholder] renders.
ProviderContainer _makeContainer({CanvasGraph? graph}) {
  final container = ProviderContainer(
    overrides: <Override>[
      canvas_sync.apiClientProvider.overrideWithValue(_FakeCanvasApiClient()),
    ],
  );

  if (graph != null) {
    container.read(studioViewModeProvider.notifier).setMode(StudioViewMode.nir);
    container.read(canvasProvider.notifier).setGraph(graph);
    container.read(nirImportProvider.notifier).state = NirImportState.loaded(
      source: NirSource.canvas,
      result: _stubInspectResult(),
      writeBackConsumed: true,
    );
    container.read(specTextProvider.notifier).set('');
  }

  return container;
}

/// Wraps [NirImporterTab] in a full [MaterialApp] using
/// [UncontrolledProviderScope] so the seeded container drives the tree.
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

bool _hasFilledRoundedDecoration(BoxDecoration? decoration) {
  if (decoration == null) return false;
  return decoration.color != null && decoration.borderRadius != null;
}

bool _isCardLikeDecoratedSurface(Widget widget) {
  // Container's internal DecoratedBox would double-count if matched here, so
  // we restrict the pattern to Container / Ink — the two carriers used by
  // call sites that produce a visibly filled+rounded surface.
  if (widget is Container) {
    final decoration = widget.decoration;
    return decoration is BoxDecoration &&
        _hasFilledRoundedDecoration(decoration);
  }
  if (widget is Ink) {
    final decoration = widget.decoration;
    return decoration is BoxDecoration &&
        _hasFilledRoundedDecoration(decoration);
  }
  return false;
}

void _expectNoNestedCards(Finder rootFinder) {
  // Walk every NmtkSurfaceCard descendant of the NIR Inspector root and
  // assert it has no descendant NmtkSurfaceCard. Re-introduction of the
  // deleted NeurocnlSectionCard / NmtkItemCard classes is enforced at the
  // source level by the zeta-card-reduction T13 governance tests.
  final surfaceCards = find.descendant(
    of: rootFinder,
    matching: find.byType(NmtkSurfaceCard),
  );
  for (final cardElement in surfaceCards.evaluate()) {
    final cardFinder = find.byWidget(cardElement.widget);
    expect(
      find.descendant(of: cardFinder, matching: find.byType(NmtkSurfaceCard)),
      findsNothing,
      reason:
          'No NmtkSurfaceCard inside the NIR Inspector subtree may have a '
          'transitive descendant NmtkSurfaceCard '
          '(zeta-theming-migration Requirements 5.1, 5.2, 5.5).',
    );
    expect(
      find.descendant(
        of: cardFinder,
        matching: find.byWidgetPredicate(
          _isCardLikeDecoratedSurface,
          description: 'Container/Ink with BoxDecoration{color, borderRadius}',
        ),
      ),
      findsNothing,
      reason:
          'No NmtkSurfaceCard inside the NIR Inspector subtree may contain a '
          'descendant Container/Ink with BoxDecoration{color, borderRadius} '
          '(zeta-theming-migration Requirement 5.2).',
    );
  }
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

  testWidgets('NirImporterTab idle view contains no NmtkSurfaceCard', (
    WidgetTester tester,
  ) async {
    final container = _makeContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(container));
    await tester.pumpAndSettle();

    // Sanity: the NIR Inspector header text renders.
    expect(find.text('NIR Inspector'), findsOneWidget);

    final rootFinder = find.byType(NirImporterTab);
    expect(rootFinder, findsOneWidget);

    // Belt-and-suspenders: zero NmtkSurfaceCard surfaces in the NIR
    // Inspector subtree at all. This matches the current implementation
    // (no NMTK card surfaces in NirImporterTab). If a future edit adds
    // one, the no-nesting invariant below is what protects against
    // regressions; this assertion captures the present state for
    // documentation. Re-introduction of the deleted NeurocnlSectionCard
    // / NmtkItemCard classes is enforced at the source level by the
    // zeta-card-reduction T13 governance tests.
    expect(
      find.descendant(of: rootFinder, matching: find.byType(NmtkSurfaceCard)),
      findsNothing,
      reason:
          'NirImporterTab idle view has no NmtkSurfaceCard ancestors '
          'today (per Task 4.2 discovery); if this changes the nested-card '
          'invariant below must continue to hold '
          '(zeta-theming-migration Requirements 5.1, 5.5, 9.6).',
    );

    // The structural invariant: vacuously true today (no NmtkSurfaceCards
    // exist), but locked so any future addition cannot nest.
    _expectNoNestedCards(rootFinder);
  });

  testWidgets(
    'NirImporterTab loaded view (with canvas graph) has no nested NmtkSurfaceCards',
    (WidgetTester tester) async {
      // Drive the loaded code path so _LoadedView and _NirGraphEditorPanel
      // render their per-node / per-edge `Card` siblings. These are Flutter
      // Material `Card`s, not NmtkSurfaceCards — they must remain flat
      // siblings of each other inside the ListView, with no NmtkSurfaceCard
      // wrapper above or between them.
      final graph = CanvasGraph(
        nodes: [
          _makeNode('input_1', nirType: 'nir.Input'),
          _makeNode('lif_1'),
        ],
        edges: [
          CanvasEdge(
            id: 'edge_input_lif',
            sourceNodeId: 'input_1',
            sourcePort: 'out',
            targetNodeId: 'lif_1',
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

      final rootFinder = find.byType(NirImporterTab);
      expect(rootFinder, findsOneWidget);

      // Sanity: the loaded view's node/edge cards render. Confirms the
      // _LoadedView / _NirGraphEditorPanel branch executed.
      expect(find.text('Node input_1'), findsOneWidget);
      expect(find.text('Node lif_1'), findsOneWidget);
      expect(find.text('Connections'), findsOneWidget);

      // Same belt-and-suspenders: the loaded NIR Inspector subtree must
      // also render zero NmtkSurfaceCard surfaces.
      expect(
        find.descendant(of: rootFinder, matching: find.byType(NmtkSurfaceCard)),
        findsNothing,
        reason:
            'NirImporterTab loaded view has no NmtkSurfaceCard ancestors '
            'today (per Task 4.2 discovery) '
            '(zeta-theming-migration Requirements 5.1, 5.5, 9.6).',
      );

      // The structural invariant — same as the idle case but exercised
      // against the richer loaded tree containing _NirNodeCard /
      // _NirEdgeList Material `Card`s.
      _expectNoNestedCards(rootFinder);
    },
  );

  // History note: zeta-card-unification Task 7 originally wrapped each
  // _NirNodeCard in an NmtkItemCard so the per-node row matched a unified
  // card surface. The follow-up zeta-card-reduction Task 9 reverses that
  // direction — the ExpansionTile is already a list-item primitive
  // (header row + chevron + body), so wrapping it in NmtkItemCard
  // duplicated the visual hierarchy and conflicted with the right-side
  // "no nested card" rule. The assertion below therefore asserts the
  // *flat* shape: each _NirNodeCard renders as exactly one ExpansionTile
  // with NO NmtkSurfaceCard ancestor inside the NirImporterTab subtree.
  //
  // The previous `find.byType(NmtkItemCard)` belt-and-suspenders assertion
  // was dropped in zeta-card-reduction Task 12 because the class itself
  // is deleted; re-introduction is enforced at source-level by the T13
  // governance tests (`zeta_first_audit_test.dart`).
  testWidgets(
    'Each _NirNodeCard renders as a flat ExpansionTile (no card wrapper)',
    (WidgetTester tester) async {
      final graph = CanvasGraph(
        nodes: [
          _makeNode('input_1', nirType: 'nir.Input'),
          _makeNode('lif_1'),
        ],
        edges: const <CanvasEdge>[],
        metadata: const {},
      );

      final container = _makeContainer(graph: graph);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      final rootFinder = find.byType(NirImporterTab);
      expect(rootFinder, findsOneWidget);

      // 2 nodes ⇒ exactly 2 ExpansionTiles (one per _NirNodeCard) inside
      // the NirImporterTab subtree.
      expect(
        find.descendant(of: rootFinder, matching: find.byType(ExpansionTile)),
        findsNWidgets(2),
        reason:
            'Each _NirNodeCard must render as exactly one ExpansionTile '
            '(zeta-card-reduction Task 9).',
      );

      // Each ExpansionTile inside NirImporterTab must remain flat: no
      // NmtkSurfaceCard ancestor below it.
      for (final Element tileElement
          in find
              .descendant(of: rootFinder, matching: find.byType(ExpansionTile))
              .evaluate()) {
        expect(
          find.descendant(
            of: find.byWidget(tileElement.widget),
            matching: find.byType(NmtkSurfaceCard),
          ),
          findsNothing,
          reason:
              'No ExpansionTile inside NirImporterTab may host an '
              'NmtkSurfaceCard descendant (zeta-card-reduction Task 9).',
        );
      }
    },
  );
}
