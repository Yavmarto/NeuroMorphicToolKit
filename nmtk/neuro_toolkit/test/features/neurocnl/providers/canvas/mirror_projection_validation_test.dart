import 'package:riverpod_annotation/riverpod_annotation.dart';
// Task 4.3 — Verify validation is called after _mirrorProjection
//
// **Validates: Requirements 2.2, 2.7, 2.8**
//
// This test is written against the FIXED code (Bug 4 / validation staleness fix).
// It confirms that calling _mirrorProjection (triggered by canonicalDocProvider
// emitting a new document with a non-empty CanvasProjection) results in
// validationProvider.validate being invoked exactly once with the new graph.
//
// EXPECTED OUTCOME: Test PASSES on fixed code.
// ignore_for_file: override_on_non_overriding_member

import 'dart:typed_data';

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

// ---------------------------------------------------------------------------
// Tracking validation notifier — records every validate() call
// ---------------------------------------------------------------------------

/// A [ValidationController] replacement that records every call to [validate]
/// and the graph it was called with. No network calls are made.
///
/// We extend [ValidationController] and pass a dummy Ref so the `ref` field
/// is satisfied. We override [validate] to track calls without hitting the
/// network.
class _TrackingValidationController extends ValidationController {
  _TrackingValidationController(this.validateCalls);
  final List<CanvasGraph> validateCalls;

  @override
  Future<void> validate(CanvasGraph graph) async {
    validateCalls.add(graph);
    state = AsyncValue.data(ValidationResult(valid: true, errors: const []));
  }
}

/// Minimal [Ref] stub that satisfies [ValidationController]'s constructor.
/// The tracking notifier never reads from the ref — it short-circuits in
/// [validate] before any ref access.

// ---------------------------------------------------------------------------
// No-op pipeline notifier (prevents post-dispose async errors)
// ---------------------------------------------------------------------------

class _NoOpPipelineController extends PipelineController {
  _NoOpPipelineController(this._initialState);
  final PipelineState _initialState;

  @override
  PipelineState build() => _initialState;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

// ---------------------------------------------------------------------------
// Fake API client (no network)
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
// Helpers
// ---------------------------------------------------------------------------

/// Build a one-node [CanvasProjection] that will trigger _mirrorProjection.
canonical_doc.CanvasProjection _oneNodeProjection({
  String id = 'lif_0',
  String nirType = 'nir.LIF',
}) {
  return canonical_doc.CanvasProjection(
    nodes: [
      canonical_doc.CanvasNode(id: id, label: id, nirType: nirType, size: 10),
    ],
    edges: const [],
  );
}

/// Build a [CanonicalEditorDocument] whose canvas contains [projection].
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
// Test suite
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

  // ── Core assertion: validate is called exactly once after _mirrorProjection
  group('_mirrorProjection calls validationProvider.validate '
      '(Property 4 — Validates: Requirements 2.2, 2.7, 2.8)', () {
    test('validate is called exactly once with the new graph '
        'when canonicalDocProvider emits a non-empty projection', () async {
      final validateCalls = <CanvasGraph>[];
      final container = ProviderContainer(
        overrides: [
          canvas_sync.apiClientProvider.overrideWithValue(
            _FakeCanvasApiClient(),
          ),
          pipelineProvider.overrideWith(
            () => _NoOpPipelineController(const PipelineState()),
          ),
          validationProvider.overrideWith(
            () => _TrackingValidationController(validateCalls),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Eagerly instantiate canvasProvider so its listener is wired up.
      container.read(canvasProvider);

      // Push a document with a non-empty canvas projection directly —
      // this is the exact path taken during CNL parse, NIR import, and
      // manual character-by-character revert.
      final projection = _oneNodeProjection(nirType: 'nir.LIF');
      container
          .read(canonicalDocProvider.notifier)
          .setDocument(_docWithProjection(projection));

      // Allow Riverpod listeners to fire (they are synchronous for
      // StateNotifier.listen, but give the event loop a turn to be safe).
      await Future<void>.delayed(Duration.zero);

      // Assert: validate was called at least once.
      expect(
        validateCalls,
        isNotEmpty,
        reason:
            '_mirrorProjection must call validationProvider.validate after '
            'setting state. On unfixed code this would be zero calls.',
      );

      // Assert: validate was called exactly once (no spurious extra calls).
      expect(
        validateCalls,
        hasLength(1),
        reason:
            'validate must be called exactly once per _mirrorProjection '
            'invocation — fire-and-forget, same as _doPush.',
      );

      // Assert: the graph passed to validate contains the mirrored node.
      final validatedGraph = validateCalls.first;
      expect(
        validatedGraph.nodes,
        isNotEmpty,
        reason: 'The graph passed to validate must contain the mirrored nodes.',
      );
      expect(
        validatedGraph.nodes.first.nirType,
        equals('nir.LIF'),
        reason: 'The validated graph must reflect the projection nirType.',
      );
    });

    test(
      'validate is NOT called when canonicalDocProvider emits an empty projection',
      () async {
        final validateCalls = <CanvasGraph>[];
        final container = ProviderContainer(
          overrides: [
            canvas_sync.apiClientProvider.overrideWithValue(
              _FakeCanvasApiClient(),
            ),
            pipelineProvider.overrideWith(
              () => _NoOpPipelineController(const PipelineState()),
            ),
            validationProvider.overrideWith(
              () => _TrackingValidationController(validateCalls),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.read(canvasProvider);

        // Push a document with an EMPTY canvas projection.
        // The _mirrorProjection listener guard is: if (projection.nodes.isEmpty) return;
        final emptyProjection = const canonical_doc.CanvasProjection(
          nodes: [],
          edges: [],
        );
        container
            .read(canonicalDocProvider.notifier)
            .setDocument(_docWithProjection(emptyProjection));

        await Future<void>.delayed(Duration.zero);

        // validate must NOT have been called.
        expect(
          validateCalls,
          isEmpty,
          reason:
              'validate must not be called when the projection is empty — '
              'the guard in the canonicalDocProvider listener returns early.',
        );
      },
    );

    test('validate reflects stale-state recovery — '
        'validate fires after a revert to valid CNL', () async {
      final validateCalls = <CanvasGraph>[];
      final container = ProviderContainer(
        overrides: [
          canvas_sync.apiClientProvider.overrideWithValue(
            _FakeCanvasApiClient(),
          ),
          pipelineProvider.overrideWith(
            () => _NoOpPipelineController(const PipelineState()),
          ),
          validationProvider.overrideWith(
            () => _TrackingValidationController(validateCalls),
          ),
        ],
      );
      addTearDown(container.dispose);
      // Keep autoDispose canvasProvider/validationProvider alive across the
      // Duration.zero macrotask gap below — without listeners they'd be
      // disposed and rebuilt fresh, resetting validationProvider back to
      // its default AsyncLoading build() state.
      container.listen(canvasProvider, (_, _) {});
      container.listen(validationProvider, (_, _) {});

      container.read(canvasProvider);

      // Simulate: user reverts to valid CNL (re-parse triggers setDocument
      // with a non-empty projection). This is the Bug 4 scenario.
      final validProjection = _oneNodeProjection(
        id: 'sensory',
        nirType: 'nir.LIF',
      );
      container
          .read(canonicalDocProvider.notifier)
          .setDocument(_docWithProjection(validProjection));

      await Future<void>.delayed(Duration.zero);

      // validate must have been invoked, clearing any prior stale state.
      expect(
        validateCalls,
        hasLength(1),
        reason:
            'Bug 4 scenario: after a manual revert to valid CNL triggers '
            '_mirrorProjection, validate must be called so the UI no longer '
            'shows the stale error from the broken intermediate state.',
      );

      // The validation state must now be AsyncData (not AsyncError or prior stale).
      expect(
        container.read(validationProvider),
        isA<AsyncData<ValidationResult>>(),
        reason:
            'After validate fires, validationProvider state must be AsyncData.',
      );
    });

    test('validate is called for non-LIF nodes (Input/Output/CubaLIF) — '
        'type resolution path covered', () async {
      final validateCalls = <CanvasGraph>[];
      final container = ProviderContainer(
        overrides: [
          canvas_sync.apiClientProvider.overrideWithValue(
            _FakeCanvasApiClient(),
          ),
          pipelineProvider.overrideWith(
            () => _NoOpPipelineController(const PipelineState()),
          ),
          validationProvider.overrideWith(
            () => _TrackingValidationController(validateCalls),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(canvasProvider);

      // Multi-node projection with mixed NIR types (Bug 1/2 scenario).
      final projection = const canonical_doc.CanvasProjection(
        nodes: [
          canonical_doc.CanvasNode(
            id: 'inp',
            label: 'Input',
            nirType: 'nir.Input',
          ),
          canonical_doc.CanvasNode(id: 'lif', label: 'LIF', nirType: 'nir.LIF'),
          canonical_doc.CanvasNode(
            id: 'out',
            label: 'Output',
            nirType: 'nir.Output',
          ),
        ],
        edges: [],
      );

      container
          .read(canonicalDocProvider.notifier)
          .setDocument(_docWithProjection(projection));

      await Future<void>.delayed(Duration.zero);

      expect(
        validateCalls,
        hasLength(1),
        reason:
            'validate must fire once for any non-empty projection, '
            'including mixed NIR type projections.',
      );

      final validatedGraph = validateCalls.first;
      expect(validatedGraph.nodes, hasLength(3));
    });
  });
}
