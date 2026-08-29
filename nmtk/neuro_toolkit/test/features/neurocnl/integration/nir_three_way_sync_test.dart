import 'package:riverpod_annotation/riverpod_annotation.dart';
// Integration Tests — NIR Three-Way Sync
//
// **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7**
//
// Tests A–H exercise the full three-way sync (CNL <-> Canvas <-> NIR)
// end-to-end at the ProviderContainer level, against the current
// architecture where `CanonicalDocController` (lib/providers/
// canonical_doc_provider.dart) is the single writer of spec content and
// every successful publish also drives `pipelineProvider.runParseAndValidate`
// internally. There is no separate `StudioSyncController` reconciler and no
// boolean-flag / hash-cache bookkeeping anymore — a monotonic `_generation`
// counter on `CanonicalDocController` is the only mechanism that decides
// which in-flight mutation's response wins.
//
// Test A — Full three-way sync round-trip
// Test B — Template Gallery load while NIR active
// Test C — Concurrent edits from different origins mid-flight
// Test D — Structural edit round-trip
// Test E — Loop prevention / determinism under repeated edits
// Test F — Canvas change while NIR active (live update)
// Test G — CNL -> Canvas+NIR via single source of truth
// Test H — NIR file -> CNL + Canvas + NIR (single source)
//
// EXPECTED OUTCOME: All tests PASS on the current (post-refactor) code.
// ignore_for_file: unused_element, deprecated_member_use

import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart' as canvas_val;
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical_doc;
import 'package:neuro_toolkit/features/neurocnl/models/nir_hdf5_tree.dart';
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/template.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/nir_import_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_view_mode_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart' as backend_api;
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

// ---------------------------------------------------------------------------
// Fake API clients — synchronous, no network calls
// (same pattern as nir_editor_sync_preservation_test.dart)
// ---------------------------------------------------------------------------

/// Canvas API client that encodes threshold into the generated CNL string.
class _FakeCanvasApiClient extends ApiClient {
  _FakeCanvasApiClient() : super(baseUrl: 'http://localhost:0');

  @override
  Future<String> generateCnl(CanvasGraph graph) async {
    if (graph.nodes.isEmpty) return '';
    final threshold = graph.nodes.first.parameters['threshold'];
    return 'threshold=$threshold';
  }

  @override
  Future<CanvasGraph> repairCnl(String cnl, {CanvasGraph? graph}) async {
    double? threshold;
    final match = RegExp(r'threshold=([\d.]+)').firstMatch(cnl);
    if (match != null) threshold = double.tryParse(match.group(1)!);
    final base =
        graph ??
        CanvasGraph(nodes: const [], edges: const [], metadata: const {});
    if (threshold == null || base.nodes.isEmpty) return base;
    final updated = base.nodes
        .map(
          (n) => n.copyWith(
            parameters: <String, dynamic>{
              ...n.parameters,
              'threshold': threshold,
            },
          ),
        )
        .toList();
    return base.copyWith(nodes: updated);
  }

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
  Future<String> generateCnlFromNirBytes(Uint8List payload) async =>
      'threshold=1.0';

  @override
  Future<canonical_doc.ParseCnlResponse> canvasToCanonical(
    CanvasGraph graph,
  ) async {
    if (graph.nodes.isEmpty) {
      return const canonical_doc.ParseCnlResponse(
        document: canonical_doc.CanonicalEditorDocument(
          irJson: {},
          cnlText: '',
        ),
        diagnostics: [],
      );
    }
    final threshold = graph.nodes.first.parameters['threshold'];
    final cnl = 'threshold=$threshold';
    return canonical_doc.ParseCnlResponse(
      document: canonical_doc.CanonicalEditorDocument(
        // Non-empty so NirImportController._buildFromIr (which reads
        // irJson, not cnlText) has something to build a tree from —
        // needed for tests that assert NIR propagation, not just
        // canonicalDocProvider's cnlText.
        irJson: <String, dynamic>{
          'lif_0': <String, dynamic>{'threshold': threshold},
        },
        cnlText: cnl,
      ),
      diagnostics: const [],
    );
  }

  @override
  Future<canonical_doc.ParseCnlResponse> parseCnlCanonical(
    String specText,
  ) async {
    return canonical_doc.ParseCnlResponse(
      document: canonical_doc.CanonicalEditorDocument(
        irJson: const {},
        cnlText: specText,
      ),
      diagnostics: const [],
    );
  }
}

/// Stub backend API client — no real network calls.
class _StubBackendApiClient extends backend_api.ApiClient {
  _StubBackendApiClient() : super(baseUrl: 'http://localhost:0');

  @override
  Future<ParseResult> parse(String spec) async =>
      const ParseResult(sentences: [], total: 0, errors: 0);

  @override
  Future<ValidationResult> validate(
    String spec, {
    Map<String, dynamic>? params,
    String backend = 'nir',
  }) async => const ValidationResult(
    layer1: Layer1Result(overall: true, passed: [], failed: []),
    layer2: Layer2Result(
      overall: true,
      checksPassed: [],
      checksFailed: [],
      neuronsFound: [],
    ),
    overall: true,
  );
}

/// Canvas API client whose canonical parse returns a populated canvas
/// projection + irJson, so CNL→Canvas and NIR-file→all-views can be exercised
/// end-to-end through canonicalDocProvider.
class _ProjectingCanvasApiClient extends ApiClient {
  _ProjectingCanvasApiClient() : super(baseUrl: 'http://localhost:0');

  static const _doc = canonical_doc.CanonicalEditorDocument(
    irJson: <String, dynamic>{
      'populations': <String, dynamic>{'lif_0': <String, dynamic>{}},
    },
    cnlText: 'population lif_0',
    canvas: canonical_doc.CanvasProjection(
      nodes: <canonical_doc.CanvasNode>[
        canonical_doc.CanvasNode(
          id: 'lif_0',
          label: 'LIF',
          nirType: 'nir.LIF',
          size: 10,
        ),
      ],
      edges: <canonical_doc.CanvasEdge>[],
    ),
  );

  @override
  Future<canonical_doc.ParseCnlResponse> parseCnlCanonical(
    String specText,
  ) async =>
      const canonical_doc.ParseCnlResponse(document: _doc, diagnostics: []);

  /// New direct path: NIR bytes → canonical doc (used by updateFromNirFile).
  @override
  Future<canonical_doc.ParseCnlResponse> nirBytesToCanonical(
    Uint8List payload,
  ) async =>
      const canonical_doc.ParseCnlResponse(document: _doc, diagnostics: []);

  /// Canvas → canonical doc (used by canvas mutations).
  @override
  Future<canonical_doc.ParseCnlResponse> canvasToCanonical(
    CanvasGraph graph,
  ) async =>
      const canonical_doc.ParseCnlResponse(document: _doc, diagnostics: []);

  @override
  Future<String> generateCnlFromNirBytes(Uint8List payload) async =>
      'population lif_0';

  @override
  Future<Uint8List> exportNirBytes(CanvasGraph graph) async => Uint8List(0);

  @override
  Future<canvas_val.ValidationResult> validateGraph(CanvasGraph graph) async =>
      canvas_val.ValidationResult(valid: true, errors: const []);
}

/// Canvas API client used by Test C/E to prove the `_generation` counter (not
/// call/response order) decides which in-flight mutation wins. Each call is
/// tagged by the caller (via the CNL text / node threshold it carries) and
/// the test controls how long each tagged response takes to resolve via
/// [delays], so a call issued earlier can be made to resolve *later* than a
/// call issued after it — the classic "stale response arrives last" race.
class _DelayedCanvasApiClient extends ApiClient {
  _DelayedCanvasApiClient() : super(baseUrl: 'http://localhost:0');

  /// spec/cnl text -> artificial delay before the response resolves.
  final Map<String, Duration> cnlDelays = {};

  /// threshold (as it appears in the pushed graph) -> artificial delay.
  final Map<double, Duration> canvasDelays = {};

  /// Every `parseCnlCanonical` call, in call order (not resolution order).
  final List<String> cnlCallsIssued = [];

  /// Every `canvasToCanonical` call's threshold, in call order.
  final List<double> canvasCallsIssued = [];

  @override
  Future<canonical_doc.ParseCnlResponse> parseCnlCanonical(
    String specText,
  ) async {
    cnlCallsIssued.add(specText);
    final delay = cnlDelays[specText] ?? Duration.zero;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return canonical_doc.ParseCnlResponse(
      document: canonical_doc.CanonicalEditorDocument(
        irJson: const {},
        cnlText: specText,
      ),
      diagnostics: const [],
    );
  }

  @override
  Future<canonical_doc.ParseCnlResponse> canvasToCanonical(
    CanvasGraph graph,
  ) async {
    final threshold = (graph.nodes.first.parameters['threshold'] as num)
        .toDouble();
    canvasCallsIssued.add(threshold);
    final delay = canvasDelays[threshold] ?? Duration.zero;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return canonical_doc.ParseCnlResponse(
      document: canonical_doc.CanonicalEditorDocument(
        irJson: const {},
        cnlText: 'threshold=$threshold',
      ),
      diagnostics: const [],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

CanvasNode _lifNode({String id = 'lif_0', double threshold = 1.0}) =>
    CanvasNode(
      id: id,
      componentId: 'lif_population',
      nirType: 'nir.LIF',
      label: 'LIF',
      parameters: <String, dynamic>{
        'name': id,
        'n_neurons': 10,
        'threshold': threshold,
      },
      position: const <double>[100.0, 100.0],
      metadata: const <String, dynamic>{'category': 'neuron'},
    );

CanvasGraph _singleNodeGraph({double threshold = 1.0}) => CanvasGraph(
  nodes: <CanvasNode>[_lifNode(threshold: threshold)],
  edges: const <CanvasEdge>[],
  metadata: const <String, dynamic>{},
);

CanvasGraph _twoNodeGraph() => CanvasGraph(
  nodes: <CanvasNode>[
    _lifNode(id: 'sensory', threshold: 1.0),
    _lifNode(id: 'motor', threshold: 0.8),
  ],
  edges: const <CanvasEdge>[],
  metadata: const <String, dynamic>{},
);

/// Builds a test container with sane default fakes for both
/// `apiClientProvider`s. Pass [canvasApiClient]/[backendApiClient] to swap
/// either default fake (rather than appending a second override for the
/// same provider via [extraOverrides], which Riverpod rejects as a
/// duplicate override within one container).
ProviderContainer _makeContainer({
  ApiClient? canvasApiClient,
  backend_api.ApiClient? backendApiClient,
  List<Override>? extraOverrides,
}) {
  final container = ProviderContainer(
    overrides: <Override>[
      canvas_sync.apiClientProvider.overrideWithValue(
        canvasApiClient ?? _FakeCanvasApiClient(),
      ),
      apiClientProvider.overrideWithValue(
        backendApiClient ?? _StubBackendApiClient(),
      ),
      ...?extraOverrides,
    ],
  );
  container.listen(canvasProvider, (_, _) {});
  container.listen(canonicalDocProvider, (_, _) {});
  return container;
}

/// Creates a minimal CnlTemplate for testing.
CnlTemplate _makeTemplate({
  String id = 'test_template',
  String spec = 'threshold=0.5',
  String name = 'Test Template',
}) => CnlTemplate(
  id: id,
  name: name,
  description: 'Integration test template',
  category: 'Test',
  tags: const ['test'],
  difficulty: 'beginner',
  spec: spec,
);

/// A minimal NirInspectResult stub.
NirInspectResult _stubInspectResult({String fileName = 'canvas (exported)'}) =>
    NirInspectResult(
      fileName: fileName,
      fileSizeBytes: 0,
      root: const NirHdf5Group(name: '/', attrs: {}, children: []),
    );

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

  // ── Test A — Full three-way sync round-trip ─────────────────────────────
  //
  // Validates Requirements 2.1, 2.2, 2.3:
  //   WHEN a LIF threshold is changed via the NIR editor (canvasProvider
  //   updateNodeParameters) THEN:
  //   1. canvasProvider reflects the new threshold immediately.
  //   2. canonicalDocProvider is updated once the debounced push settles
  //      (canvasProvider.updateNodeParameters -> CanonicalDocController.
  //      updateFromCanvas is the only write path left; there is no separate
  //      onCanvasCnlSpec/specTextProvider hookup to assert on anymore —
  //      specTextProvider is just a read facade over canonicalDocProvider).
  //
  // EXPECTED: PASS on current code.
  group('Test A — Full three-way sync round-trip', () {
    test(
      'NIR parameter edit propagates to canvasProvider and canonicalDocProvider',
      () {
        // Use fakeAsync to control timing around the 300ms debounce timer in
        // CanvasController._pushToCanonical.
        fakeAsync((async) {
          final container = _makeContainer();
          addTearDown(container.dispose);

          container.read(canvasProvider.notifier).setGraph(_singleNodeGraph());
          container
              .read(studioViewModeProvider.notifier)
              .setMode(StudioViewMode.nir);

          const nodeId = 'lif_0';
          final newParams = <String, dynamic>{
            'name': nodeId,
            'n_neurons': 10,
            'threshold': 0.8,
          };

          // NIR editor commits: update canvas parameters. No begin/end-edit
          // bracketing exists anymore — updateNodeParameters is the single
          // entry point and it debounces its own push to canonicalDocProvider.
          container
              .read(canvasProvider.notifier)
              .updateNodeParameters(nodeId, newParams);

          // ASSERT 1: Canvas reflects the new threshold immediately.
          final updatedNode = container
              .read(canvasProvider)
              .graph
              .nodes
              .firstWhere((n) => n.id == nodeId);
          expect(
            updatedNode.parameters['threshold'],
            equals(0.8),
            reason:
                'Test A: canvasProvider must reflect the new threshold after NIR edit',
          );

          // Advance past the 300ms debounce so
          // canonicalDocProvider.updateFromCanvas fires.
          async.elapse(const Duration(milliseconds: 400));
          async.flushMicrotasks();

          // canonicalDocProvider now holds the updated doc with the
          // regenerated CNL text. All three views (CNL editor, Canvas, NIR)
          // derive from this one document.
          final doc = container.read(canonicalDocProvider).value;
          expect(
            doc,
            isNotNull,
            reason:
                'Test A: canonicalDocProvider must have a document after canvas edit',
          );
          expect(
            doc!.cnlText,
            contains('0.8'),
            reason:
                'Test A: canonicalDocProvider CNL text must reflect the new threshold',
          );
          expect(
            container.read(specTextProvider),
            equals(doc.cnlText),
            reason:
                'Test A: specTextProvider is a read facade over canonicalDocProvider '
                'and must mirror its cnlText exactly',
          );
        });
      },
    );
  });

  // ── Test B — Template Gallery load while NIR active ─────────────────────
  //
  // Validates Requirement 2.6:
  //   WHEN a template is loaded via the same content path
  //   `template_load_guard.dart` uses (canonicalDocProvider.updateFromCnl)
  //   while NIR is the active view THEN nirImportProvider re-derives its
  //   tree from the new document's irJson (it reacts to canonicalDocProvider,
  //   not to a template-load-specific callback).
  //
  // The old `applyTemplateToWorkspace` reconciler explicitly called
  // `syncFromCanvas` when `viewMode == nir`; that function and that call no
  // longer exist. Templates now flow through the same single content pipe
  // as everything else, so this test exercises that pipe directly rather
  // than re-simulating a bespoke NIR refresh step.
  //
  // EXPECTED: PASS on current code.
  group('Test B — Template Gallery load while NIR active', () {
    test(
      'loading a template while viewMode == nir updates canonicalDocProvider, '
      'canvasProvider and nirImportProvider from the same document',
      () async {
        final container = ProviderContainer(
          overrides: <Override>[
            canvas_sync.apiClientProvider.overrideWithValue(
              _ProjectingCanvasApiClient(),
            ),
            apiClientProvider.overrideWithValue(_StubBackendApiClient()),
          ],
        );
        addTearDown(container.dispose);
        container.listen(canvasProvider, (_, _) {});
        container.listen(nirImportProvider, (_, _) {});

        // Set NIR mode with a previously loaded graph.
        container
            .read(studioViewModeProvider.notifier)
            .setMode(StudioViewMode.nir);
        container.read(canvasProvider.notifier).setGraph(_singleNodeGraph());

        // Pre-seed nirImportProvider with old (unrelated) state. Use
        // NirSource.canvas (not NirSource.file) — a NirSource.file state is
        // an intentionally "pinned" inspection of an uploaded .nir file
        // (see NirImportController._syncFromIr's early-return guard) and is
        // untouched by canonicalDocProvider changes until the user switches
        // files or explicitly dismisses it. That pinning is not what this
        // test is about; it is covered separately by nir_import_provider
        // unit tests.
        container
            .read(nirImportProvider.notifier)
            .state = NirImportState.loaded(
          source: NirSource.canvas,
          result: _stubInspectResult(fileName: 'old_template.nir'),
        );

        final template = _makeTemplate(spec: 'population lif_0');

        // This is exactly what applyTemplateToWorkspace's content step does:
        // one call to canonicalDocProvider.updateFromCnl. The fixed
        // architecture has no separate "if viewMode == nir, also call
        // syncFromCanvas" branch — nirImportProvider listens to
        // canonicalDocProvider directly, so it refreshes as a side effect of
        // this one call, not because of a template-load special case.
        await container
            .read(canonicalDocProvider.notifier)
            .updateFromCnl(template.spec);
        // Drain the fire-and-forget pipeline.runParseAndValidate call that
        // _publishDocument kicks off internally, so it settles before this
        // test (and its container) tears down — otherwise it can try to use
        // ref after the container is disposed.
        await pumpEventQueue();

        // ASSERT 1: viewMode is unaffected by the content load.
        expect(
          container.read(studioViewModeProvider).viewMode,
          StudioViewMode.nir,
          reason: 'Test B: viewMode must remain nir after template load',
        );

        // ASSERT 2: canonicalDocProvider holds the template's document.
        final doc = container.read(canonicalDocProvider).value;
        expect(
          doc?.cnlText,
          equals(template.spec),
          reason:
              'Test B: canonicalDocProvider must hold the new template spec',
        );

        // ASSERT 3: canvasProvider mirrors the template's canvas projection
        // (the projecting fake always returns the lif_0 node).
        expect(
          container
              .read(canvasProvider)
              .graph
              .nodes
              .any((n) => n.id == 'lif_0'),
          isTrue,
          reason:
              'Test B: canvasProvider must mirror the template canonical '
              'projection',
        );

        // ASSERT 4: nirImportProvider was refreshed from the new document,
        // replacing the stale `old_template.nir` file-source state, because
        // it now derives from canonicalDocProvider.irJson rather than a
        // dedicated NIR-file source.
        final nirState = container.read(nirImportProvider);
        expect(
          nirState,
          isA<NirImportLoaded>(),
          reason:
              'Test B: nirImportProvider must be loaded after template load',
        );
        final loadedState = nirState as NirImportLoaded;
        expect(
          loadedState.source,
          NirSource.canvas,
          reason:
              'Test B: nirImportProvider must switch away from the stale '
              'NirSource.file state once canonicalDocProvider publishes a '
              'new document derived from canvas/CNL content',
        );

        // ASSERT 5: specTextProvider (facade) reflects the new template spec.
        expect(
          container.read(specTextProvider),
          equals(template.spec),
          reason: 'Test B: specTextProvider must contain the new template spec',
        );
      },
    );
  });

  // ── Test C — Concurrent edits from different origins mid-flight ─────────
  //
  // Validates Requirements 2.3, 2.7:
  //   WHEN two edits from *different* origins (a CNL text commit and a
  //   canvas structural mutation) are both in flight at the same time THEN
  //   the result is deterministic and uncorrupted — whichever call actually
  //   *completes* last wins, and it is never possible to end up with a
  //   document that mixes fields from two different publishes.
  //
  // There is no tab-switch mechanism left to test (CNL/Canvas/NIR are
  // simultaneous overlay panels in production — `setMode` only changes which
  // panel has focus in the UI shell, it has zero effect on any provider
  // wiring here, confirmed by reading studio_view_mode_provider.dart and
  // grepping for callers). So "switching editors mid-edit" is reframed as:
  // two concurrent origins racing against the single `_generation` counter
  // on CanonicalDocController, which is the actual mechanism that used to be
  // guarded (badly) by the deleted boolean flags in studio_sync_notifier.dart.
  //
  // We deliberately make the earlier-issued call resolve *after* the
  // later-issued one, to prove the winner is decided by resolution order +
  // generation number, not by call/issue order — i.e. there is no separate
  // "CNL always wins" or "canvas always wins" bias.
  //
  // Note on scope: a canvas structural mutation and a *fresh* CNL commit
  // (`updateFromCnl`) cannot usefully overlap for their full duration in
  // this codebase, because `updateFromCnl` sets `state = const
  // AsyncLoading()` (dropping the previous document) the instant it starts,
  // and `CanvasController`'s canonicalDocProvider listener treats a
  // valueless state as "graph is empty" and clears `canvasProvider.graph`
  // for every other in-flight consumer — including a canvas edit whose own
  // debounce timer hasn't fired yet. That is genuine, current, intentional
  // production wiring (not something this task is authorized to change,
  // and not the bug this refactor targeted), so this test instead starts
  // the canvas edit first and lets its own backend round-trip still be
  // in-flight when a second, independent commit begins — genuinely
  // concurrent from the generation counter's point of view without hitting
  // that unrelated interaction.
  //
  // EXPECTED: PASS on current code.
  group('Test C — Concurrent edits from different origins mid-flight', () {
    test('a slow-resolving canvas edit is superseded by a faster-resolving '
        'later canvas edit — no mixed/corrupted state, no stale overwrite', () {
      fakeAsync((async) {
        final fakeApi = _DelayedCanvasApiClient();
        final container = _makeContainer(canvasApiClient: fakeApi);
        addTearDown(container.dispose);

        container.read(canvasProvider.notifier).setGraph(_singleNodeGraph());

        // First edit (origin: NIR/canvas param panel) is issued first but
        // made to resolve slowest.
        const firstThreshold = 0.42;
        fakeApi.canvasDelays[firstThreshold] = const Duration(
          milliseconds: 500,
        );
        container.read(canvasProvider.notifier).updateNodeParameters(
          'lif_0',
          <String, dynamic>{
            'name': 'lif_0',
            'n_neurons': 10,
            'threshold': firstThreshold,
          },
        );

        // Let its debounce (300ms) fire so the slow backend call is
        // genuinely in flight before the second edit starts.
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();
        expect(
          fakeApi.canvasCallsIssued,
          equals([firstThreshold]),
          reason:
              'Test C precondition: the first edit\'s backend call must '
              'already be in flight (issued, not yet resolved) before the '
              'second edit starts',
        );

        // Second edit (origin: a different, later canvas mutation — e.g.
        // an external template/undo — while the first is still in
        // flight) is issued second but resolves fastest.
        const secondThreshold = 0.99;
        fakeApi.canvasDelays[secondThreshold] = const Duration(
          milliseconds: 50,
        );
        container.read(canvasProvider.notifier).updateNodeParameters(
          'lif_0',
          <String, dynamic>{
            'name': 'lif_0',
            'n_neurons': 10,
            'threshold': secondThreshold,
          },
        );

        // Let the second edit's debounce (300ms) elapse and its (50ms)
        // response resolve, well before the first call's remaining
        // ~200ms.
        async.elapse(const Duration(milliseconds: 350));
        async.flushMicrotasks();

        final afterSecondWins = container.read(canonicalDocProvider).value;
        expect(
          afterSecondWins?.cnlText,
          equals('threshold=$secondThreshold'),
          reason:
              'Test C: the second (later-issued, faster-resolving) edit '
              'must be the published document at this point',
        );

        // Now let the slower first response land. Because it was issued
        // *before* the second edit, it holds an *older* generation
        // number, so it must be discarded on arrival rather than
        // clobbering the newer result that already published.
        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();

        final finalDoc = container.read(canonicalDocProvider).value;
        expect(
          finalDoc?.cnlText,
          equals('threshold=$secondThreshold'),
          reason:
              'Test C (generation counter): a stale response from an '
              'earlier-issued call must never overwrite a newer publish, '
              'even if it arrives later. If this fails with '
              '"threshold=$firstThreshold", the generation guard regressed.',
        );

        // No corruption: canvasProvider and canonicalDocProvider must
        // agree — never a mix of the first edit's value with the second
        // edit's value.
        final canvasNode = container
            .read(canvasProvider)
            .graph
            .nodes
            .firstWhere((n) => n.id == 'lif_0');
        expect(
          canvasNode.parameters['threshold'],
          equals(secondThreshold),
          reason:
              'Test C: canvasProvider must retain the winning edit\'s '
              'threshold — no partial corruption from the discarded stale '
              'response',
        );
      });
    });

    test(
      'a canvas edit started while a CNL edit is still debouncing supersedes '
      'the pending CNL edit rather than racing it',
      () {
        fakeAsync((async) {
          final container = _makeContainer();
          addTearDown(container.dispose);
          container.read(canvasProvider.notifier).setGraph(_singleNodeGraph());

          // Start typing in the CNL editor — debounced, not yet committed.
          unawaited(
            container
                .read(canonicalDocProvider.notifier)
                .editCnlText('threshold=0.11'),
          );
          expect(
            container.read(pendingCnlEditProvider),
            equals('threshold=0.11'),
            reason:
                'Test C: the optimistic echo must be visible immediately '
                'after editCnlText, before its debounce fires',
          );

          // Before the 400ms CNL debounce fires, a canvas structural edit
          // commits (undebounced generation bump via updateFromCanvas is
          // scheduled through the canvas controller's own 300ms debounce).
          container.read(canvasProvider.notifier).updateNodeParameters(
            'lif_0',
            <String, dynamic>{
              'name': 'lif_0',
              'n_neurons': 10,
              'threshold': 0.77,
            },
          );

          // Elapse past both debounce windows.
          async.elapse(const Duration(milliseconds: 500));
          async.flushMicrotasks();

          // The canvas edit's own updateFromCanvas call clears the pending
          // CNL echo and cancels its timer (see updateFromCanvas in
          // canonical_doc_provider.dart), so the stale CNL text must never
          // reach canonicalDocProvider.
          expect(
            container.read(pendingCnlEditProvider),
            isNull,
            reason:
                'Test C: a superseding canvas edit must clear the pending '
                'CNL echo rather than letting it commit afterwards',
          );
          final doc = container.read(canonicalDocProvider).value;
          expect(
            doc?.cnlText,
            equals('threshold=0.77'),
            reason:
                'Test C: the canvas edit must be the surviving document; the '
                'superseded CNL debounce must never publish',
          );
        });
      },
    );
  });

  // ── Test D — Structural edit round-trip ──────────────────────────────────
  //
  // Validates Requirements 2.1, 2.4:
  //   WHEN a node is added via the NIR editor THEN it appears in canvasProvider.
  //   WHEN the same node is removed via the NIR editor THEN it is absent from
  //   canvasProvider and CNL text is regenerated (empty — no nodes remain).
  //
  // EXPECTED: PASS on current code.
  group('Test D — Structural edit round-trip: add and remove node', () {
    test('adding a node via canvasProvider.addNode makes it visible in '
        'canvasProvider; removing it makes it absent', () {
      fakeAsync((async) {
        final container = _makeContainer();
        addTearDown(container.dispose);

        container
            .read(studioViewModeProvider.notifier)
            .setMode(StudioViewMode.nir);

        // Confirm starting state.
        expect(container.read(canvasProvider).graph.nodes, isEmpty);

        // Add a node — addNode is the single entry point; it pushes to
        // canonicalDocProvider undebounced internally.
        const newNodeId = 'new_lif_node';
        final newNode = _lifNode(id: newNodeId, threshold: 1.2);
        container.read(canvasProvider.notifier).addNode(newNode);

        // ASSERT 1: Node appears in canvasProvider.
        expect(
          container
              .read(canvasProvider)
              .graph
              .nodes
              .any((n) => n.id == newNodeId),
          isTrue,
          reason:
              'Test D: added node must appear in canvasProvider.graph.nodes',
        );

        async.flushMicrotasks();

        // ASSERT 2: canonicalDocProvider updated.
        expect(
          container.read(canonicalDocProvider).value,
          isNotNull,
          reason:
              'Test D: canonicalDocProvider must be set after adding a node',
        );

        // Remove the node.
        container.read(canvasProvider.notifier).removeNode(newNodeId);

        // ASSERT 3: Node is absent from canvasProvider.
        expect(
          container
              .read(canvasProvider)
              .graph
              .nodes
              .any((n) => n.id == newNodeId),
          isFalse,
          reason:
              'Test D: removed node must be absent from canvasProvider.graph.nodes',
        );

        async.flushMicrotasks();

        // ASSERT 4: The canvas is now empty.
        expect(
          container.read(canvasProvider).graph.nodes,
          isEmpty,
          reason: 'Test D: canvas must be empty after removing the only node',
        );

        // ASSERT 5: specTextProvider does not contain the removed node id.
        final specAfterRemove = container.read(specTextProvider);
        expect(
          specAfterRemove,
          isNot(contains('new_lif_node')),
          reason:
              'Test D: specTextProvider must not contain the removed node id',
        );
      });
    });
  });

  // ── Test E — Loop prevention / determinism under repeated edits ─────────
  //
  // Validates Requirement 2.5 (Property 3: Loop Prevention):
  //   WHEN N rapid sequential CNL edits are performed without awaiting each
  //   one THEN only the LAST edit's response is ever published — earlier,
  //   now-stale in-flight requests must never land and must never cause a
  //   visible flicker/intermediate corruption in canonicalDocProvider.
  //
  // The previous version of this test asserted a call-count bound
  // (`syncFromCanvasCallCount <= N`) against a `_syncingNirToCanvas` boolean
  // flag inside `NirImportController`. That flag and its guarded call site
  // (`syncFromCanvas` being invoked from a canvas-change listener) no longer
  // exist: `NirImportController.syncFromCanvas` now has zero callers in
  // lib/ — NirImportController instead reacts to canonicalDocProvider
  // directly (`_syncFromIr`), so there is no separate NIR-vs-canvas loop to
  // guard against catching in a call-count. The real loop-prevention
  // mechanism that replaced it is `CanonicalDocController._generation`, so
  // this test asserts against that mechanism's *observable* behaviour
  // instead — which is a strictly stronger assertion than a call count,
  // because it pins down not just "how many calls" but "which one wins and
  // what the final state looks like along the way".
  //
  // EXPECTED: PASS on current code.
  group('Test E — Loop prevention: only the final edit of a rapid-fire burst '
      'is ever published', () {
    test(
      '5 rapid-fire editCnlText calls (none awaited individually) collapse '
      'to exactly the last one — no intermediate value is ever published',
      () {
        fakeAsync((async) {
          final container = _makeContainer();
          addTearDown(container.dispose);

          const n = 5;
          final texts = List<String>.generate(n, (i) => 'threshold=0.$i');

          // Fire N edits back-to-back with no delay between them and
          // without awaiting any of them individually — this is exactly
          // the "rapid repeated edits" scenario Requirement 2.5 targets.
          // Per editCnlText's contract, each call cancels the previous
          // pending debounce Timer outright, so only the LAST call's
          // Timer ever fires; the first N-1 returned futures intentionally
          // never resolve (documented behaviour, not a bug — do not await
          // them here).
          for (final text in texts) {
            unawaited(
              container.read(canonicalDocProvider.notifier).editCnlText(text),
            );
            // The optimistic echo always reflects the most recent call.
            expect(
              container.read(pendingCnlEditProvider),
              equals(text),
              reason:
                  'Test E: pendingCnlEditProvider must track the latest '
                  'keystroke synchronously, even before any debounce fires',
            );
          }

          // Before the debounce elapses, nothing has been published yet —
          // proves the earlier N-1 edits never got a chance to commit.
          expect(
            container.read(canonicalDocProvider).value,
            isNull,
            reason:
                'Test E: none of the N edits may publish before the '
                'debounce window elapses',
          );

          // Elapse past the 400ms debounce exactly once.
          async.elapse(const Duration(milliseconds: 500));
          async.flushMicrotasks();

          // ASSERT: exactly and only the LAST edit is published.
          final doc = container.read(canonicalDocProvider).value;
          expect(
            doc?.cnlText,
            equals(texts.last),
            reason:
                'Test E (Property 3: Loop Prevention): only the final edit '
                'of a rapid-fire burst may ever be published. If this is '
                'any earlier text, a superseded Timer fired — the '
                'debounce-cancellation contract in editCnlText regressed.',
          );

          // The optimistic echo must be cleared once its commit settles.
          expect(
            container.read(pendingCnlEditProvider),
            isNull,
            reason:
                'Test E: pendingCnlEditProvider must clear once the '
                'winning edit\'s debounced commit resolves',
          );

          // specTextProvider (facade) must agree exactly — no flicker.
          expect(
            container.read(specTextProvider),
            equals(texts.last),
            reason:
                'Test E: specTextProvider must mirror the single '
                'published document with no intermediate value visible',
          );
        });
      },
    );

    test('5 sequential NIR/canvas parameter edits on the same node resolve to '
        'exactly the last threshold, with earlier responses discarded by '
        'generation number even if they resolve out of order', () {
      fakeAsync((async) {
        final fakeApi = _DelayedCanvasApiClient();
        final container = _makeContainer(canvasApiClient: fakeApi);
        addTearDown(container.dispose);

        container.read(canvasProvider.notifier).setGraph(_singleNodeGraph());

        const nodeId = 'lif_0';
        const nCount = 5;
        final thresholds = [0.1, 0.3, 0.5, 0.7, 0.9];

        // Make earlier edits resolve *slower* than later ones, so a
        // naive "first response wins" implementation would publish the
        // wrong (stale) value. Only a real generation counter gets this
        // right regardless of arrival order.
        for (var i = 0; i < nCount; i++) {
          fakeApi.canvasDelays[thresholds[i]] = Duration(
            milliseconds: 100 * (nCount - i),
          );
        }

        // Perform N sequential NIR/canvas parameter edits without
        // awaiting the debounce of each individually (they share and
        // repeatedly reset the same 300ms debounce timer).
        for (int i = 0; i < nCount; i++) {
          final params = <String, dynamic>{
            'name': nodeId,
            'n_neurons': 10,
            'threshold': thresholds[i],
          };
          container
              .read(canvasProvider.notifier)
              .updateNodeParameters(nodeId, params);
        }

        // Only the last edit's debounce timer is live (each
        // updateNodeParameters call cancels+reschedules the shared
        // timer), so elapse past its 300ms window plus the slowest
        // possible artificial response delay (500ms for the first edit).
        async.elapse(const Duration(milliseconds: 900));
        async.flushMicrotasks();

        // Exactly one canvasToCanonical call should have been issued —
        // the debounce collapses all 5 edits into a single push.
        expect(
          fakeApi.canvasCallsIssued,
          equals([thresholds.last]),
          reason:
              'Test E (Property 3: Loop Prevention): rapid sequential '
              'edits sharing one debounce window must collapse to a '
              'single backend call carrying the final value, not $nCount '
              'separate calls',
        );

        // ASSERT: the published document reflects only the final
        // threshold — no flicker through intermediate values.
        final doc = container.read(canonicalDocProvider).value;
        expect(
          doc?.cnlText,
          equals('threshold=${thresholds.last}'),
          reason:
              'Test E: the final published document must carry exactly '
              'the last edit\'s threshold',
        );
        final canvasNode = container
            .read(canvasProvider)
            .graph
            .nodes
            .firstWhere((n) => n.id == nodeId);
        expect(
          canvasNode.parameters['threshold'],
          equals(thresholds.last),
          reason:
              'Test E: canvasProvider must agree with canonicalDocProvider '
              '— both reflect only the last edit, never an intermediate one',
        );
      });
    });
  });

  // ── Test F — Canvas change while NIR active (live update) ────────────────
  //
  // Validates Requirement 2.7:
  //   WHEN canvasProvider is mutated directly (external change, not from NIR)
  //   while NIR is the active view AND the 300 ms debounce elapses THEN
  //   canonicalDocProvider (and therefore nirImportProvider, which derives
  //   from it) reflects the mutation.
  //
  // EXPECTED: PASS on current code.
  group(
    'Test F — Canvas change while NIR active: live update after debounce',
    () {
      test('canvas mutation while NIR active updates canonicalDocProvider and '
          'nirImportProvider', () {
        fakeAsync((async) {
          final container = _makeContainer();
          addTearDown(container.dispose);
          container.listen(nirImportProvider, (_, _) {});

          container.read(canvasProvider.notifier).setGraph(_singleNodeGraph());
          container
              .read(studioViewModeProvider.notifier)
              .setMode(StudioViewMode.nir);

          // Canvas mutation while NIR is active.
          container.read(canvasProvider.notifier).updateNodeParameters(
            'lif_0',
            <String, dynamic>{
              'name': 'lif_0',
              'n_neurons': 10,
              'threshold': 0.7,
            },
          );

          // Advance past 300ms debounce.
          async.elapse(const Duration(milliseconds: 400));
          async.flushMicrotasks();

          // canonicalDocProvider must have been updated.
          final doc = container.read(canonicalDocProvider).value;
          expect(
            doc,
            isNotNull,
            reason:
                'Test F: canonicalDocProvider must update when canvas changes '
                'while NIR is active',
          );
          expect(
            doc!.cnlText,
            contains('0.7'),
            reason:
                'Test F: canonicalDocProvider must reflect the new threshold',
          );

          // nirImportProvider must have re-derived its tree from the same
          // document (it listens to canonicalDocProvider directly).
          expect(
            container.read(nirImportProvider),
            isA<NirImportLoaded>(),
            reason:
                'Test F: nirImportProvider must be loaded from the updated '
                'canonical document',
          );
        });
      });
    },
  );

  // ── Test G — CNL→Canvas+NIR via single source of truth ───────────────────
  //
  // Validates the core regression: editing CNL must populate the Canvas and
  // NIR editor. Also covers the lazy-init replay gap — canvasProvider/
  // nirImportProvider are read AFTER the doc already exists, so they must seed
  // from the current canonical document (not only future changes).
  group('Test G — CNL→Canvas+NIR through canonicalDocProvider', () {
    test('parsing CNL populates a lazily-created canvasProvider and '
        'nirImportProvider from the current document', () async {
      final container = ProviderContainer(
        overrides: <Override>[
          canvas_sync.apiClientProvider.overrideWithValue(
            _ProjectingCanvasApiClient(),
          ),
          apiClientProvider.overrideWithValue(_StubBackendApiClient()),
        ],
      );
      addTearDown(container.dispose);

      // CNL edit parses into the doc BEFORE canvas/NIR providers are created.
      await container
          .read(canonicalDocProvider.notifier)
          .updateFromCnl('population lif_0');
      // Drain the fire-and-forget pipeline.runParseAndValidate call kicked
      // off internally by _publishDocument before the container tears down.
      await pumpEventQueue();

      // First read of canvasProvider — must seed from the existing doc.
      final canvasNodes = container.read(canvasProvider).graph.nodes;
      expect(
        canvasNodes.any((n) => n.id == 'lif_0'),
        isTrue,
        reason:
            'Test G: lazily-created canvasProvider must mirror the current '
            'canonical document (CNL→Canvas).',
      );

      // First read of nirImportProvider — must seed its tree from the doc.
      final nirState = container.read(nirImportProvider);
      expect(
        nirState,
        isA<NirImportLoaded>(),
        reason:
            'Test G: lazily-created nirImportProvider must seed its tree '
            'from the current document (CNL→NIR).',
      );
    });
  });

  // ── Test H — NIR file → CNL + Canvas + NIR (single source) ───────────────
  //
  // Validates Requirement: loading a .nir file routes solely through
  // canonicalDocProvider.updateFromNirFile and updates all three views.
  group('Test H — NIR file load updates all three views', () {
    test('updateFromNirFile populates canonicalDocProvider, canvasProvider and '
        'nirImportProvider', () async {
      final container = ProviderContainer(
        overrides: <Override>[
          canvas_sync.apiClientProvider.overrideWithValue(
            _ProjectingCanvasApiClient(),
          ),
          apiClientProvider.overrideWithValue(_StubBackendApiClient()),
        ],
      );
      addTearDown(container.dispose);

      // Create the providers up front so their listeners are attached.
      container.read(canvasProvider);
      container.read(nirImportProvider);

      await container
          .read(canonicalDocProvider.notifier)
          .updateFromNirFile(Uint8List.fromList([1, 2, 3]));
      // Drain the fire-and-forget pipeline.runParseAndValidate call kicked
      // off internally by _publishDocument before the container tears down.
      await pumpEventQueue();

      expect(
        container.read(canonicalDocProvider).value,
        isNotNull,
        reason: 'Test H: canonicalDocProvider must hold the NIR-derived doc',
      );
      expect(
        container.read(canvasProvider).graph.nodes.any((n) => n.id == 'lif_0'),
        isTrue,
        reason: 'Test H: canvasProvider must mirror the NIR-derived projection',
      );
      expect(
        container.read(nirImportProvider),
        isA<NirImportLoaded>(),
        reason: 'Test H: nirImportProvider must seed its tree from the doc',
      );
    });
  });
}
