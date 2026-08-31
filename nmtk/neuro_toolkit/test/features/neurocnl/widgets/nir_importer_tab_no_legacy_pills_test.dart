import 'package:riverpod_annotation/riverpod_annotation.dart';
// Regression test for zeta-card-reduction Task 11: the NIR Inspector tab
// (NirImporterTab) renders its source badge + file-metadata pills as
// ZetaAssistChip and its write-back confirmation as NmtkStatusBanner —
// not as hand-rolled BoxDecoration containers with hard-coded hex colors
// (#00897B, #7C4DFF, AppTheme.surfaceVariant, etc.).
//
// Mirror of `deploy_workspace_no_section_card_test.dart` and
// `validation_panel_no_nested_cards_test.dart` for the "flat shape" rule
// applied to the NIR Inspector header + loaded view. Validates the Zeta
// primitive map captured in
// `docs/current tasks/2026-05-26-zeta-card-reduction-handoff.md` §5
// (rows 14 + 15 — `_SourceBadge`/`_MetaChip` → `ZetaAssistChip`,
// `_WriteBackBanner` → `NmtkStatusBanner`).
//
// Validates: zeta-card-reduction Task 11.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
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

NirInspectResult _stubInspectResult({
  String fileName = 'test.nir',
  int fileSizeBytes = 128,
}) => NirInspectResult(
  fileName: fileName,
  fileSizeBytes: fileSizeBytes,
  root: const NirHdf5Group(name: '/', attrs: {}, children: []),
);

ProviderContainer _makeContainer({
  NirImportState? nirState,
  CanvasGraph? graph,
}) {
  final container = ProviderContainer(
    overrides: <Override>[
      canvas_sync.apiClientProvider.overrideWithValue(_FakeCanvasApiClient()),
    ],
  );
  if (graph != null) {
    container.read(canvasProvider.notifier).setGraph(graph);
  }
  if (nirState != null) {
    container.read(studioViewModeProvider.notifier).setMode(StudioViewMode.nir);
    container.read(nirImportProvider.notifier).state = nirState;
    container.read(specTextProvider.notifier).set('');
  }
  return container;
}

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

  testWidgets(
    "NirImporterTab idle: source badge renders as ZetaAssistChip(label: 'idle')",
    (WidgetTester tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // Sanity: the NIR Inspector header text renders.
      expect(find.text('NIR Inspector'), findsOneWidget);

      // T11: _SourceBadge → ZetaAssistChip(label: 'idle').
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ZetaAssistChip && widget.label == 'idle',
          description: "ZetaAssistChip(label: 'idle')",
        ),
        findsOneWidget,
        reason:
            'The source badge in the NIR Inspector header must render as '
            "ZetaAssistChip(label: 'idle') after zeta-card-reduction Task 11.",
      );

      // No write-back banner in the idle view.
      expect(find.byType(NmtkStatusBanner), findsNothing);
    },
  );

  testWidgets(
    'NirImporterTab loaded: 1 source chip + 3 metadata chips, all ZetaAssistChip',
    (WidgetTester tester) async {
      final container = _makeContainer(
        nirState: NirImportState.loaded(
          source: NirSource.canvas,
          result: _stubInspectResult(fileName: 'demo.nir', fileSizeBytes: 2048),
          writeBackConsumed: true,
        ),
        graph: CanvasGraph(
          nodes: const [],
          edges: const [],
          metadata: const {},
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final rootFinder = find.byType(NirImporterTab);
      expect(rootFinder, findsOneWidget);

      // 1 source badge + 3 metadata chips = 4 ZetaAssistChip instances total.
      // The metadata chips are: filename, size label, items count.
      expect(
        find.descendant(of: rootFinder, matching: find.byType(ZetaAssistChip)),
        findsNWidgets(4),
        reason:
            'Loaded NirImporterTab must render exactly 4 ZetaAssistChip '
            'instances: 1 source badge + 3 metadata pills (filename, size, '
            'items count) — zeta-card-reduction Task 11.',
      );

      // Source chip carries the 'from canvas' label for NirSource.canvas.
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ZetaAssistChip && widget.label == 'from canvas',
          description: "ZetaAssistChip(label: 'from canvas')",
        ),
        findsOneWidget,
      );

      // Filename chip carries the .nir file name.
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ZetaAssistChip && widget.label == 'demo.nir',
          description: "ZetaAssistChip(label: 'demo.nir')",
        ),
        findsOneWidget,
      );

      // No NmtkStatusBanner in canvas-source loaded view (the write-back
      // banner is gated on source == NirSource.file).
      expect(
        find.descendant(
          of: rootFinder,
          matching: find.byType(NmtkStatusBanner),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'NirImporterTab loaded with file write-back: NmtkStatusBanner renders',
    (WidgetTester tester) async {
      final container = _makeContainer(
        nirState: NirImportState.loaded(
          source: NirSource.file,
          result: _stubInspectResult(),
          writeBackConsumed: true, // suppress the post-frame _applyWriteBack
        ),
        graph: CanvasGraph(
          nodes: const [],
          edges: const [],
          metadata: const {},
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final rootFinder = find.byType(NirImporterTab);
      expect(rootFinder, findsOneWidget);

      // T11: _WriteBackBanner → NmtkStatusBanner with success tone.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is NmtkStatusBanner &&
              widget.title == 'Synced to CNL editor & Canvas' &&
              widget.tone == NmtkTone.success &&
              widget.icon == ZetaIcons.sync,
          description:
              "NmtkStatusBanner(title: 'Synced to CNL editor & Canvas', "
              'tone: success, icon: ZetaIcons.sync)',
        ),
        findsOneWidget,
        reason:
            'Write-back confirmation must render as a success-toned '
            'NmtkStatusBanner — zeta-card-reduction Task 11.',
      );

      // The source chip in the file-source case carries 'from file'.
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ZetaAssistChip && widget.label == 'from file',
          description: "ZetaAssistChip(label: 'from file')",
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('NirImporterTab post-T12: zero NmtkSurfaceCard descendants', (
    WidgetTester tester,
  ) async {
    final container = _makeContainer(
      nirState: NirImportState.loaded(
        source: NirSource.file,
        result: _stubInspectResult(),
        writeBackConsumed: true,
      ),
      graph: CanvasGraph(nodes: const [], edges: const [], metadata: const {}),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final rootFinder = find.byType(NirImporterTab);
    expect(rootFinder, findsOneWidget);

    expect(
      find.descendant(of: rootFinder, matching: find.byType(NmtkSurfaceCard)),
      findsNothing,
      reason:
          'NirImporterTab must contain zero NmtkSurfaceCard descendants '
          'after zeta-card-reduction T9 + T11. Re-introduction of the '
          'deleted NeurocnlSectionCard / NmtkItemCard classes is enforced '
          'at the source level by the T13 governance tests.',
    );
  });

  testWidgets(
    'NirImporterTab header: source badge subtree contains no hand-rolled pill '
    'BoxDecoration',
    (WidgetTester tester) async {
      // The header is the most exposed surface for the legacy hand-rolled
      // pill pattern (Container + BoxDecoration with hard-coded hex colour
      // and border-radius). After T11 the source badge is a ZetaAssistChip
      // whose own decoration lives inside _ZetaChipState (an
      // AnimatedContainer, not a plain Container with a hex colour). This
      // test asserts the absence of the legacy pattern in the header
      // subtree by searching for ZetaAssistChip's parent Row and verifying
      // no `Container(decoration: BoxDecoration(color, borderRadius))`
      // sibling exists with a hand-coded fill colour.
      final container = _makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // Locate the ZetaAssistChip rendered for the source badge.
      final chipFinder = find.byWidgetPredicate(
        (widget) => widget is ZetaAssistChip && widget.label == 'idle',
        description: "ZetaAssistChip(label: 'idle')",
      );
      expect(chipFinder, findsOneWidget);

      // Walk up to the header Row by finding the nearest enclosing Row that
      // also contains the 'NIR Inspector' text. We then assert that no
      // *direct* Container / DecoratedBox with a BoxDecoration{color +
      // borderRadius} exists between the chip and that Row beyond the
      // chip's own internal decoration. This is a structural smoke test
      // — the chip itself contains an AnimatedContainer with a Zeta-token
      // colour + radius, which is allowed; the assertion targets explicit
      // hand-rolled `Container(decoration: BoxDecoration(color: …))`
      // sibling pills accidentally added back into the header.
      //
      // Concretely: there must be no DecoratedBox whose decoration's color
      // matches the legacy hardcoded hex values (#00897B, #7C4DFF). This
      // catches accidental restoration of the pre-T11 colour palette.
      const legacyHexColors = <int>[
        0xFF00897B, // teal — write-back banner
        0xFF7C4DFF, // purple — canvas source pill
      ];
      expect(
        find.byWidgetPredicate((widget) {
          if (widget is! Container && widget is! DecoratedBox) return false;
          final decoration = widget is Container
              ? widget.decoration
              : (widget as DecoratedBox).decoration;
          if (decoration is! BoxDecoration) return false;
          final color = decoration.color;
          if (color == null) return false;
          // Compare the opaque RGB component only — the legacy code used
          // .withValues(alpha: 0.10/0.12/0.35) on the fill, but those
          // helpers preserve the RGB triplet which is what we want to
          // detect.
          final argb = color.toARGB32();
          for (final legacy in legacyHexColors) {
            if ((argb & 0x00FFFFFF) == (legacy & 0x00FFFFFF)) return true;
          }
          return false;
        }, description: 'Container/DecoratedBox with legacy hex pill colour'),
        findsNothing,
        reason:
            'No descendant in NirImporterTab may carry the pre-T11 hand-'
            'rolled pill colour palette (#00897B, #7C4DFF). The source '
            'badge, metadata chips, and write-back banner are now Zeta '
            'primitives — zeta-card-reduction Task 11.',
      );
    },
  );
}
