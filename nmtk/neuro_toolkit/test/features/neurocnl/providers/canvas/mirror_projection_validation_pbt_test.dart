import 'package:riverpod_annotation/riverpod_annotation.dart';
// Task 7.4 — PBT: Validation Always Follows _mirrorProjection
//
// **Validates: Requirements 2.2, 2.7, 2.8**
//
// Property 4: Bug Condition — Validation After _mirrorProjection
//
// For any non-empty CanvasProjection (arbitrary node count 1–10 with
// arbitrary NIR types drawn from the known type set), calling
// _mirrorProjection on a fresh CanvasController (with mock validationProvider)
// always results in validationProvider.validate being invoked at least once.
//
// Confirms no code path inside _mirrorProjection can skip the validate call.
//
// Run on FIXED code — EXPECTED OUTCOME: all 100 generated cases PASS.
// ignore_for_file: override_on_non_overriding_member

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical_doc;
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/validation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// NIR type universe — all types known to _nirTypeToComponentId
// ---------------------------------------------------------------------------

/// All NIR primitive type strings against which the fix is tested.
/// Drawn from the _nirTypeToComponentId map in canvas_projection_utils.dart.
const _kNirTypes = <String>[
  'nir.LIF',
  'nir.Input',
  'nir.Output',
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
// Tracking validation notifier — records every validate() call (no network)
// ---------------------------------------------------------------------------

class _TrackingValidationController extends ValidationController {
  _TrackingValidationController(this.validateCalls);
  final List<CanvasGraph> validateCalls;

  @override
  Future<void> validate(CanvasGraph graph) async {
    validateCalls.add(graph);
    state = AsyncValue.data(ValidationResult(valid: true, errors: const []));
  }
}

// ---------------------------------------------------------------------------
// No-op pipeline notifier
// ---------------------------------------------------------------------------

class _NoOpPipelineController extends PipelineController {
  _NoOpPipelineController(this._initialState);
  final PipelineState _initialState;

  @override
  PipelineState build() => _initialState;

  // runParseAndValidate is a concrete inherited method — noSuchMethod never
  // intercepts it, so it must be overridden directly (CanonicalDocController
  // now calls it from every _publishDocument).
  @override
  Future<void> runParseAndValidate(
    String spec, {
    String? backendOverride,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

// ---------------------------------------------------------------------------
// Fake API client (no network calls)
// ---------------------------------------------------------------------------

class _FakeCanvasApiClient extends ApiClient {
  _FakeCanvasApiClient() : super(baseUrl: 'http://localhost:0');

  @override
  Future<String> generateCnl(CanvasGraph graph) async => '';

  @override
  Future<CanvasGraph> repairCnl(String cnl, {CanvasGraph? graph}) async {
    return graph ??
        CanvasGraph(nodes: const [], edges: const [], metadata: const {});
  }

  @override
  Future<ImportNirBytesResponse> importNirBytes(Uint8List payload) async {
    return ImportNirBytesResponse(
      graph: CanvasGraph(nodes: const [], edges: const [], metadata: const {}),
    );
  }

  @override
  Future<Uint8List> exportNirBytes(CanvasGraph graph) async => Uint8List(0);

  @override
  Future<String> generateCnlFromNirBytes(Uint8List payload) async => '';
}

// ---------------------------------------------------------------------------
// Generator: arbitrary non-empty CanvasProjection (1–10 nodes)
// ---------------------------------------------------------------------------

/// Draw a random NIR type string from [_kNirTypes].
String _drawNirType(Random rng) => _kNirTypes[rng.nextInt(_kNirTypes.length)];

/// Build a [CanvasProjection] with [nodeCount] nodes, each carrying a
/// randomly chosen NIR type. No edges are needed to exercise the property.
canonical_doc.CanvasProjection _arbitraryProjection(
  Random rng, {
  required int nodeCount,
}) {
  assert(nodeCount >= 1 && nodeCount <= 10);
  final nodes = List<canonical_doc.CanvasNode>.generate(
    nodeCount,
    (i) => canonical_doc.CanvasNode(
      id: 'node_$i',
      label: 'Node $i',
      nirType: _drawNirType(rng),
      size: rng.nextInt(100) + 1,
    ),
  );
  return canonical_doc.CanvasProjection(nodes: nodes, edges: const []);
}

/// Wrap a [canonical_doc.CanvasProjection] in a minimal
/// [canonical_doc.CanonicalEditorDocument] so it can be fed into
/// [canonicalDocProvider] via [setDocument].
canonical_doc.CanonicalEditorDocument _docWithProjection(
  canonical_doc.CanvasProjection projection,
) {
  return canonical_doc.CanonicalEditorDocument(
    irJson: const <String, dynamic>{},
    cnlText: '',
    canvas: projection,
  );
}

// ---------------------------------------------------------------------------
// Property runner helpers
// ---------------------------------------------------------------------------

/// Create a fresh, isolated [ProviderContainer] wired with the tracking
/// notifier so each property trial is independent.
///
/// A `ProviderContainer()` on its own is NOT enough: CanonicalDocController
/// persists every published document into ServerConfigService (a static,
/// SharedPreferences-mock-backed store) via
/// WorkspaceController.setActiveFileCanonicalDocument, and WorkspaceController
/// restores from that same store on build() when nothing else seeds it. The
/// mock store survives across `ProviderContainer` instances within one
/// `test()` body (setUp/setUpAll only reset it once per test, not per loop
/// iteration) — so trial N's projection leaks into trial N+1's "fresh"
/// container as its initial state unless reset here too.
Future<(ProviderContainer, List<CanvasGraph>)> _freshContainer() async {
  SharedPreferences.setMockInitialValues({});
  ServerConfigService.debugResetForTests();
  await ServerConfigService.initialize();
  final validateCalls = <CanvasGraph>[];
  final container = ProviderContainer(
    overrides: [
      canvas_sync.apiClientProvider.overrideWithValue(_FakeCanvasApiClient()),
      pipelineProvider.overrideWith(
        () => _NoOpPipelineController(const PipelineState()),
      ),
      validationProvider.overrideWith(
        () => _TrackingValidationController(validateCalls),
      ),
    ],
  );
  container.read(canvasProvider);
  return (container, validateCalls);
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

  group('PBT — validate always follows _mirrorProjection '
      '(Property 4 — Validates: Requirements 2.2, 2.7, 2.8)', () {
    // ── Core property: 100 random (nodeCount, nirTypes) inputs ─────────────
    test(
      'For any non-empty CanvasProjection (1–10 nodes, arbitrary NIR types), '
      '_mirrorProjection always invokes validationProvider.validate at least once',
      () async {
        // Deterministic seed → reproducible counterexamples on failure.
        final rng = Random(42);

        // Run 100 independent trials covering all node counts 1–10 and a
        // wide sample of random NIR type combinations.
        const trials = 100;
        for (var trial = 0; trial < trials; trial++) {
          // Vary node count uniformly across [1, 10].
          final nodeCount = (trial % 10) + 1;
          final projection = _arbitraryProjection(rng, nodeCount: nodeCount);

          final (container, tracking) = await _freshContainer();
          addTearDown(container.dispose);
          container.listen(canvasProvider, (_, _) {});

          // Trigger _mirrorProjection via the canonicalDocProvider listener.
          container
              .read(canonicalDocProvider.notifier)
              .setDocument(_docWithProjection(projection));

          // Give the Riverpod listener one event-loop turn.
          await Future<void>.delayed(Duration.zero);

          // Property: validate was called at least once.
          expect(
            tracking,
            isNotEmpty,
            reason:
                'Trial $trial (nodeCount=$nodeCount, '
                'nirTypes=${projection.nodes.map((n) => n.nirType).toList()}): '
                '_mirrorProjection must call validationProvider.validate after '
                'setting state. This would fail on unfixed code (Bug 4).',
          );

          // Additional: the validated graph carries the expected node count.
          final validatedGraph = tracking.first;
          expect(
            validatedGraph.nodes.length,
            equals(nodeCount),
            reason:
                'Trial $trial: graph passed to validate must contain all '
                '$nodeCount mirrored nodes.',
          );
        }
      },
    );

    // ── Full sweep across every distinct node count 1–10 ──────────────────
    for (var n = 1; n <= 10; n++) {
      final nodeCount = n;
      test(
        'nodeCount=$nodeCount — validate fires for projections of $nodeCount node(s)',
        () async {
          final rng = Random(nodeCount * 137);
          final projection = _arbitraryProjection(rng, nodeCount: nodeCount);

          final (container, tracking) = await _freshContainer();
          addTearDown(container.dispose);
          container.listen(canvasProvider, (_, _) {});

          container
              .read(canonicalDocProvider.notifier)
              .setDocument(_docWithProjection(projection));

          await Future<void>.delayed(Duration.zero);

          expect(
            tracking,
            isNotEmpty,
            reason:
                '_mirrorProjection must call validate for a projection with '
                '$nodeCount node(s). '
                'Types: ${projection.nodes.map((n) => n.nirType).toList()}',
          );

          expect(
            tracking.first.nodes.length,
            equals(nodeCount),
            reason:
                'Graph passed to validate must contain exactly $nodeCount node(s).',
          );
        },
      );
    }

    // ── Property: all NIR types individually trigger validate ──────────────
    for (final nirType in _kNirTypes) {
      test(
        'nirType=$nirType — validate fires when projection contains only $nirType nodes',
        () async {
          final projection = canonical_doc.CanvasProjection(
            nodes: [
              canonical_doc.CanvasNode(
                id: 'node_0',
                label: 'Node 0',
                nirType: nirType,
                size: 1,
              ),
            ],
            edges: const [],
          );

          final (container, tracking) = await _freshContainer();
          addTearDown(container.dispose);
          container.listen(canvasProvider, (_, _) {});

          container
              .read(canonicalDocProvider.notifier)
              .setDocument(_docWithProjection(projection));

          await Future<void>.delayed(Duration.zero);

          expect(
            tracking,
            isNotEmpty,
            reason:
                '_mirrorProjection must call validate regardless of NIR type. '
                'Failed for nirType=$nirType.',
          );
        },
      );
    }

    // ── Property: validate is called exactly once per _mirrorProjection ────
    test('validate is called exactly once per _mirrorProjection invocation '
        '(no spurious duplicate calls) — 50 random trials', () async {
      final rng = Random(99);

      for (var trial = 0; trial < 50; trial++) {
        final nodeCount = (trial % 10) + 1;
        final projection = _arbitraryProjection(rng, nodeCount: nodeCount);

        final (container, tracking) = await _freshContainer();
        addTearDown(container.dispose);
        container.listen(canvasProvider, (_, _) {});

        container
            .read(canonicalDocProvider.notifier)
            .setDocument(_docWithProjection(projection));

        await Future<void>.delayed(Duration.zero);

        expect(
          tracking,
          hasLength(1),
          reason:
              'Trial $trial (nodeCount=$nodeCount): validate must be called '
              'exactly once — fire-and-forget, same as _doPush. '
              'Got ${tracking.length} calls.',
        );
      }
    });

    // ── Property: null nirType nodes still trigger validate ─────────────────
    test('null nirType — validate fires even when all nodes have nirType=null '
        '(pre-fix backend backward compatibility path)', () async {
      final rng = Random(7);
      final nodeCount = rng.nextInt(10) + 1;

      final nodes = List<canonical_doc.CanvasNode>.generate(
        nodeCount,
        (i) => canonical_doc.CanvasNode(
          id: 'node_$i',
          label: 'Node $i',
          // nirType intentionally null — simulates pre-fix backend response.
          size: 1,
        ),
      );
      final projection = canonical_doc.CanvasProjection(
        nodes: nodes,
        edges: const [],
      );

      final (container, tracking) = await _freshContainer();
      addTearDown(container.dispose);
      container.listen(canvasProvider, (_, _) {});

      container
          .read(canonicalDocProvider.notifier)
          .setDocument(_docWithProjection(projection));

      await Future<void>.delayed(Duration.zero);

      expect(
        tracking,
        isNotEmpty,
        reason:
            '_mirrorProjection must call validate even when all projection '
            'nodes have nirType=null (backwards-compatible pre-fix backend).',
      );
    });

    // ── Guard: empty projection does NOT trigger validate ──────────────────
    test(
      'empty projection — validate is NOT called when projection.nodes is empty',
      () async {
        final emptyProjection = const canonical_doc.CanvasProjection(
          nodes: [],
          edges: [],
        );

        final (container, tracking) = await _freshContainer();
        addTearDown(container.dispose);
        container.listen(canvasProvider, (_, _) {});

        container
            .read(canonicalDocProvider.notifier)
            .setDocument(_docWithProjection(emptyProjection));

        await Future<void>.delayed(Duration.zero);

        expect(
          tracking,
          isEmpty,
          reason:
              'The canonicalDocProvider listener guard returns early when '
              'projection.nodes.isEmpty — validate must not fire.',
        );
      },
    );
  });
}
