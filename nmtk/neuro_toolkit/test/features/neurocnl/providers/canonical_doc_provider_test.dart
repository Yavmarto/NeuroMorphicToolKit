import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart' as cd;
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    show CanonicalEditorDocument;
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart' as pipeline_api;
import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart' as pipeline_client;
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

// ---------------------------------------------------------------------------
// Fake pipeline API client — every CanonicalDocController publish now
// triggers PipelineController.runParseAndValidate (single-owner design: the
// canonical doc is the one place that decides "content changed, re-validate"
// instead of three separate sync functions each remembering to call it).
// That uses a *different* apiClientProvider (api_provider.dart) than the one
// canvas/NIR translation uses (canvas/sync_provider.dart) — both need a fake
// for this container to stay hermetic. Throwing is fine: PipelineController
// catches and sets an error state; these tests only assert canonicalDoc's
// own state, not pipeline's.
// ---------------------------------------------------------------------------

class _FakePipelineApi extends pipeline_client.ApiClient {
  _FakePipelineApi() : super(baseUrl: 'http://localhost:0');

  @override
  Future<ParseResult> parse(String spec) async {
    throw Exception('not mocked in canonicalDocProvider tests');
  }

  @override
  Future<ValidationResult> validate(
    String spec, {
    Map<String, dynamic>? params,
    String backend = 'nir',
  }) async {
    throw Exception('not mocked in canonicalDocProvider tests');
  }
}

// ---------------------------------------------------------------------------
// Fake API client
// ---------------------------------------------------------------------------

/// A fake whose [parseCnlCanonical] resolution is caller-controlled, for
/// precisely interleaving two "in-flight at once" requests — the scenario
/// the generation counter exists to handle (a stale response landing after
/// a newer edit already won).
class _ControllableFakeApi extends ApiClient {
  _ControllableFakeApi() : super(baseUrl: 'http://localhost:0');

  final Map<String, Completer<cd.ParseCnlResponse>> _pending = {};

  Completer<cd.ParseCnlResponse> completerFor(String spec) =>
      _pending.putIfAbsent(spec, () => Completer<cd.ParseCnlResponse>());

  @override
  Future<cd.ParseCnlResponse> parseCnlCanonical(String specText) =>
      completerFor(specText).future;
}

cd.ParseCnlResponse _responseFor(String cnlText) => cd.ParseCnlResponse(
  document: cd.CanonicalEditorDocument(irJson: const {}, cnlText: cnlText),
  diagnostics: const [],
);

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://localhost:0');

  @override
  Future<cd.ParseCnlResponse> parseCnlCanonical(String specText) async =>
      cd.ParseCnlResponse(
        document: cd.CanonicalEditorDocument(
          irJson: const {},
          cnlText: specText,
          canvas: const cd.CanvasProjection(
            nodes: [cd.CanvasNode(id: 'n1', label: 'N1', size: 1)],
            edges: [],
          ),
        ),
        diagnostics: const [],
      );

  @override
  Future<cd.ParseCnlResponse> canvasToCanonical(CanvasGraph graph) async =>
      cd.ParseCnlResponse(
        document: cd.CanonicalEditorDocument(
          irJson: const {},
          cnlText: 'from_canvas',
          canvas: cd.CanvasProjection(
            nodes: graph.nodes
                .map((n) => cd.CanvasNode(id: n.id, label: n.id, size: 1))
                .toList(),
            edges: const [],
          ),
        ),
        diagnostics: const [],
      );

  @override
  Future<cd.ParseCnlResponse> nirBytesToCanonical(Uint8List payload) async =>
      const cd.ParseCnlResponse(
        document: cd.CanonicalEditorDocument(
          irJson: {},
          cnlText: 'from_nir_canonical',
          canvas: cd.CanvasProjection(
            nodes: [cd.CanvasNode(id: 'nir_node', label: 'NirNode', size: 1)],
            edges: [],
          ),
        ),
        diagnostics: [],
      );
}

ProviderContainer _makeContainer() => ProviderContainer(
  overrides: [
    canvas_sync.apiClientProvider.overrideWithValue(_FakeApi()),
    pipeline_api.apiClientProvider.overrideWithValue(_FakePipelineApi()),
  ],
);

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

  group('canonicalDocProvider — updateFromCnl', () {
    test('transitions Loading → AsyncData with parsed doc', () async {
      final c = _makeContainer();
      addTearDown(c.dispose);

      await c.read(canonicalDocProvider.notifier).updateFromCnl('test cnl');

      final state = c.read(canonicalDocProvider);
      expect(state, isA<AsyncData<CanonicalEditorDocument?>>());
      expect(state.value?.cnlText, 'test cnl');
    });

    test('empty string clears doc', () async {
      final c = _makeContainer();
      addTearDown(c.dispose);

      await c.read(canonicalDocProvider.notifier).updateFromCnl('test cnl');
      await c.read(canonicalDocProvider.notifier).updateFromCnl('');

      expect(c.read(canonicalDocProvider).value, isNull);
    });

    test('cnlText getter returns current cnl', () async {
      final c = _makeContainer();
      addTearDown(c.dispose);

      await c.read(canonicalDocProvider.notifier).updateFromCnl('hello');

      expect(c.read(canonicalDocProvider.notifier).cnlText, 'hello');
    });
  });

  group('canonicalDocProvider — updateFromCanvas', () {
    test('transitions Loading → AsyncData with derived doc', () async {
      final c = _makeContainer();
      addTearDown(c.dispose);

      final graph = CanvasGraph(
        nodes: [
          CanvasNode(
            id: 'pop_a',
            componentId: 'lif_population',
            parameters: const {},
            position: const [0, 0],
          ),
        ],
        edges: const [],
        metadata: const {},
      );
      await c.read(canonicalDocProvider.notifier).updateFromCanvas(graph);

      final doc = c.read(canonicalDocProvider).value;
      expect(doc?.cnlText, 'from_canvas');
      expect(doc?.canvas?.nodes.first.id, 'pop_a');
    });

    test('empty graph is a no-op', () async {
      final c = _makeContainer();
      addTearDown(c.dispose);

      await c.read(canonicalDocProvider.notifier).updateFromCnl('original');
      await c
          .read(canonicalDocProvider.notifier)
          .updateFromCanvas(
            CanvasGraph(nodes: const [], edges: const [], metadata: const {}),
          );

      // doc unchanged — empty graph skipped
      expect(c.read(canonicalDocProvider).value?.cnlText, 'original');
    });
  });

  group('canonicalDocProvider — updateFromNirFile', () {
    test('derives canonical doc directly from NIR bytes', () async {
      final c = _makeContainer();
      addTearDown(c.dispose);

      await c
          .read(canonicalDocProvider.notifier)
          .updateFromNirFile(Uint8List(4));

      final doc = c.read(canonicalDocProvider).value;
      // nirBytesToCanonical returns a single 'nir_node' canvas node.
      expect(doc?.cnlText, 'from_nir_canonical');
      expect(doc?.canvas?.nodes.length, 1);
      expect(doc?.canvas?.nodes.first.id, 'nir_node');
    });
  });

  group('canonicalDocProvider — setDocument / clear', () {
    test('setDocument stores doc directly', () {
      final c = _makeContainer();
      addTearDown(c.dispose);

      const doc = cd.CanonicalEditorDocument(irJson: {}, cnlText: 'direct');
      c.read(canonicalDocProvider.notifier).setDocument(doc);

      expect(c.read(canonicalDocProvider).value?.cnlText, 'direct');
    });

    test('clear resets to null', () {
      final c = _makeContainer();
      addTearDown(c.dispose);

      const doc = cd.CanonicalEditorDocument(irJson: {}, cnlText: 'x');
      c.read(canonicalDocProvider.notifier).setDocument(doc);
      c.read(canonicalDocProvider.notifier).clear();

      expect(c.read(canonicalDocProvider).value, isNull);
    });
  });

  group('canonicalDocProvider — generation counter (supersession)', () {
    test('a stale in-flight commit does not clobber a newer one that already '
        'resolved — the exact race the old boolean-flag/hash-cache '
        'reconciler used to guard against', () async {
      final api = _ControllableFakeApi();
      final c = ProviderContainer(
        overrides: [
          canvas_sync.apiClientProvider.overrideWithValue(api),
          pipeline_api.apiClientProvider.overrideWithValue(_FakePipelineApi()),
        ],
      );
      addTearDown(c.dispose);
      final notifier = c.read(canonicalDocProvider.notifier);

      final stale = notifier.updateFromCnl('stale');
      final fresh = notifier.updateFromCnl('fresh');

      // Resolve the newer edit first, exactly as a real network race would.
      api.completerFor('fresh').complete(_responseFor('fresh'));
      await fresh;
      expect(c.read(canonicalDocProvider).value?.cnlText, 'fresh');

      // The older edit's response arrives late — it must be dropped, not
      // overwrite the already-published newer document.
      api.completerFor('stale').complete(_responseFor('stale'));
      await stale;
      expect(c.read(canonicalDocProvider).value?.cnlText, 'fresh');
    });

    test('generation bumps across mutation types too — a canvas edit fired '
        'after an in-flight CNL edit wins', () async {
      final api = _ControllableFakeApi();
      final c = ProviderContainer(
        overrides: [
          canvas_sync.apiClientProvider.overrideWithValue(api),
          pipeline_api.apiClientProvider.overrideWithValue(_FakePipelineApi()),
        ],
      );
      addTearDown(c.dispose);
      final notifier = c.read(canonicalDocProvider.notifier);

      final staleCnl = notifier.updateFromCnl('stale_cnl');
      notifier.setDocument(
        const cd.CanonicalEditorDocument(irJson: {}, cnlText: 'direct_set'),
      );
      expect(c.read(canonicalDocProvider).value?.cnlText, 'direct_set');

      api.completerFor('stale_cnl').complete(_responseFor('stale_cnl'));
      await staleCnl;
      expect(c.read(canonicalDocProvider).value?.cnlText, 'direct_set');
    });
  });

  group('canonicalDocProvider — editCnlText (live typing)', () {
    test('sets the optimistic echo synchronously, clears it once the '
        'debounced commit settles', () async {
      final c = _makeContainer();
      addTearDown(c.dispose);
      final notifier = c.read(canonicalDocProvider.notifier);

      final commit = notifier.editCnlText(
        'typed text',
        debounce: Duration.zero,
      );
      // Echo is visible immediately — before the debounce/backend round trip.
      expect(c.read(pendingCnlEditProvider), 'typed text');

      await commit;

      expect(c.read(pendingCnlEditProvider), isNull);
      expect(c.read(canonicalDocProvider).value?.cnlText, 'typed text');
    });

    test('a second keystroke before the debounce fires cancels the first '
        'commit outright — only the latest text is ever sent', () async {
      final c = _makeContainer();
      addTearDown(c.dispose);
      final notifier = c.read(canonicalDocProvider.notifier);

      // debounce: 0 still schedules a Timer(0) rather than committing
      // synchronously, so calling editCnlText again before the event loop
      // turns cancels the first timer outright — its returned future never
      // resolves (the commit it was for was abandoned), so only the second
      // call's future is awaited here.
      final firstCommit = notifier.editCnlText(
        'first',
        debounce: Duration.zero,
      );
      final secondCommit = notifier.editCnlText(
        'first and more',
        debounce: Duration.zero,
      );
      expect(c.read(pendingCnlEditProvider), 'first and more');

      await secondCommit;

      expect(c.read(pendingCnlEditProvider), isNull);
      expect(c.read(canonicalDocProvider).value?.cnlText, 'first and more');
      // The cancelled first commit's future is intentionally left unresolved
      // (nothing awaits it in production either) — reference it so the
      // analyzer doesn't flag it as unused.
      expect(firstCommit, isA<Future<void>>());
    });

    test('flushPendingCnlEdit commits immediately without waiting for the '
        'debounce', () async {
      final c = _makeContainer();
      addTearDown(c.dispose);
      final notifier = c.read(canonicalDocProvider.notifier);

      unawaited(
        notifier.editCnlText('flush me', debounce: const Duration(seconds: 30)),
      );
      expect(c.read(pendingCnlEditProvider), 'flush me');

      await notifier.flushPendingCnlEdit();

      expect(c.read(pendingCnlEditProvider), isNull);
      expect(c.read(canonicalDocProvider).value?.cnlText, 'flush me');
    });

    test(
      'preserves pendingCnlEditProvider and specTextProvider on parse failure so editor is not cleared or reverted',
      () async {
        final container = ProviderContainer(
          overrides: [
            canvas_sync.apiClientProvider.overrideWithValue(_FailingApi()),
            pipeline_api.apiClientProvider.overrideWithValue(
              _FakePipelineApi(),
            ),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(canonicalDocProvider.notifier);

        final commit = notifier.editCnlText(
          'invalid cnl sentence',
          debounce: Duration.zero,
        );
        expect(container.read(pendingCnlEditProvider), 'invalid cnl sentence');
        expect(container.read(specTextProvider), 'invalid cnl sentence');

        await commit;

        // Upon parse error, pendingCnlEditProvider must NOT be cleared to null
        expect(container.read(pendingCnlEditProvider), 'invalid cnl sentence');
        expect(container.read(specTextProvider), 'invalid cnl sentence');
      },
    );
  });
}

class _FailingApi extends ApiClient {
  _FailingApi() : super(baseUrl: 'http://localhost:0');

  @override
  Future<cd.ParseCnlResponse> parseCnlCanonical(String specText) async {
    throw Exception('Failed to parse CNL (canonical)');
  }
}
