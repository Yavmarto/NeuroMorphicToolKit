import 'package:riverpod_annotation/riverpod_annotation.dart';
// Task 4.4 — Verify validation is called after applyTemplateToWorkspace
//
// **Validates: Requirements 2.2, 2.5**
//
// Property 1 sub-check: Validation Always Follows applyTemplateToWorkspace
//
// Two cases are covered:
//   • Non-empty graph after template load — validate IS called with the graph
//   • Empty graph after template load   — validate is NOT called (guard)
//
// Both tests run on the FIXED code and are EXPECTED TO PASS.
//
// Architecture note:
//   canonicalDocProvider and validationProvider both consume
//   canvas_sync.apiClientProvider (canvas_api_client.ApiClient).
//   A single fake override handles parseCnlCanonical (feeds canonicalDocProvider)
//   and validateGraph (observed by the test assertions).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart'
    as canvas_validation;
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical_doc;
import 'package:neuro_toolkit/features/neurocnl/models/template.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/services/template_load_guard.dart';

// ---------------------------------------------------------------------------
// Fake canvas API client (non-empty nodes case)
//
// Extends canvas_api_client.ApiClient (the type vended by
// canvas_sync.apiClientProvider). Overrides:
//   • parseCnlCanonical — returns a two-node projection so _mirrorProjection
//     populates canvasProvider.
//   • validateGraph    — records calls so we can assert validate was invoked.
// ---------------------------------------------------------------------------

class _FakeCanvasApiWithNodes extends ApiClient {
  _FakeCanvasApiWithNodes() : super(baseUrl: 'http://localhost:0');

  int validateCallCount = 0;
  CanvasGraph? lastValidatedGraph;

  @override
  Future<canonical_doc.ParseCnlResponse> parseCnlCanonical(
    String specText,
  ) async {
    return canonical_doc.ParseCnlResponse(
      document: canonical_doc.CanonicalEditorDocument(
        irJson: const <String, dynamic>{},
        cnlText: specText,
        canvas: const canonical_doc.CanvasProjection(
          nodes: <canonical_doc.CanvasNode>[
            canonical_doc.CanvasNode(id: 'pop_a', label: 'pop_a'),
            canonical_doc.CanvasNode(id: 'pop_b', label: 'pop_b'),
          ],
          edges: <canonical_doc.CanvasEdge>[
            canonical_doc.CanvasEdge(source: 'pop_a', target: 'pop_b'),
          ],
        ),
      ),
    );
  }

  @override
  Future<canvas_validation.ValidationResult> validateGraph(
    CanvasGraph graph,
  ) async {
    validateCallCount++;
    lastValidatedGraph = graph;
    return canvas_validation.ValidationResult(valid: true, errors: const []);
  }
}

// ---------------------------------------------------------------------------
// Fake canvas API client (empty nodes case)
//
// parseCnlCanonical returns an empty projection; canvasProvider stays empty
// so the validate guard is exercised.
// ---------------------------------------------------------------------------

class _FakeCanvasApiEmpty extends ApiClient {
  _FakeCanvasApiEmpty() : super(baseUrl: 'http://localhost:0');

  int validateCallCount = 0;

  @override
  Future<canonical_doc.ParseCnlResponse> parseCnlCanonical(
    String specText,
  ) async {
    return canonical_doc.ParseCnlResponse(
      document: canonical_doc.CanonicalEditorDocument(
        irJson: const <String, dynamic>{},
        cnlText: specText,
        // Empty projection — no nodes → canvasProvider stays empty.
        canvas: const canonical_doc.CanvasProjection(
          nodes: <canonical_doc.CanvasNode>[],
          edges: <canonical_doc.CanvasEdge>[],
        ),
      ),
    );
  }

  @override
  Future<canvas_validation.ValidationResult> validateGraph(
    CanvasGraph graph,
  ) async {
    validateCallCount++;
    return canvas_validation.ValidationResult(valid: true, errors: const []);
  }
}

// ---------------------------------------------------------------------------
// No-op PipelineController — prevents real HTTP calls in runParseAndValidate
// ---------------------------------------------------------------------------

class _NoOpPipelineController extends PipelineController {
  _NoOpPipelineController(this._initialState);
  final PipelineState _initialState;

  @override
  PipelineState build() => _initialState;

  @override
  Future<void> runParseAndValidate(
    String spec, {
    String? backendOverride,
  }) async {
    // No-op — avoids network calls in tests.
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

// ---------------------------------------------------------------------------
// CnlTemplate fixtures
// ---------------------------------------------------------------------------

const _templateWithNodes = CnlTemplate(
  id: 'test_template',
  name: 'Test Template',
  description: 'Template used in tests.',
  category: 'Test',
  tags: ['test'],
  difficulty: 'beginner',
  validationBackend: 'nir',
  spec: 'populations: pop_a, pop_b; connections: pop_a -> pop_b',
);

const _templateEmpty = CnlTemplate(
  id: 'empty_template',
  name: 'Empty Template',
  description: 'Template that produces no canvas nodes.',
  category: 'Test',
  tags: ['test'],
  difficulty: 'beginner',
  validationBackend: 'nir',
  // Empty spec — parseCnlCanonical returns no nodes.
  spec: '',
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

  // ── Non-empty graph case ─────────────────────────────────────────────────
  //
  // parseCnlCanonical returns two nodes → canvasProvider ends up non-empty →
  // applyTemplateToWorkspace MUST call validationProvider.validate.
  //
  // EXPECTED OUTCOME: PASS on fixed code.
  testWidgets(
    'applyTemplateToWorkspace — validate IS called when canvas has nodes '
    '(non-empty graph case)',
    (WidgetTester tester) async {
      final fakeApi = _FakeCanvasApiWithNodes();

      final container = ProviderContainer(
        overrides: <Override>[
          canvas_sync.apiClientProvider.overrideWithValue(fakeApi),
          pipelineProvider.overrideWith(
            () => _NoOpPipelineController(const PipelineState()),
          ),
          workspaceBootstrapProvider.overrideWithValue(
            const WorkspaceBootstrap(),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(canvasProvider, (_, _) {});

      late WidgetRef capturedRef;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  capturedRef = ref;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Pre-initialize canvasProvider so its constructor registers the
      // canonicalDocProvider listener BEFORE applyTemplateToWorkspace runs.
      // (Riverpod providers are lazily initialized; the CanvasController listener
      // that calls _mirrorProjection is only registered when canvasProvider
      // is first accessed.)
      container.read(canvasProvider);

      // Call the function under test.
      await applyTemplateToWorkspace(capturedRef, _templateWithNodes);

      // Flush the Riverpod listener that fires _mirrorProjection (microtask)
      // and the unawaited validate Future.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The canvas must now be non-empty.
      final graph = container.read(canvasProvider).graph;
      expect(
        graph.nodes,
        isNotEmpty,
        reason:
            'canvasProvider must have nodes after the template load for the '
            'non-empty branch to execute.',
      );

      // CORE ASSERTION: validate was called at least once.
      expect(
        fakeApi.validateCallCount,
        greaterThanOrEqualTo(1),
        reason:
            'Property 1 (Task 4.4): validationProvider.validate MUST be called '
            'with the populated canvas graph after applyTemplateToWorkspace '
            'completes on a non-empty canvas. '
            'Bug 2 fix: applyTemplateToWorkspace reads canvasProvider.graph and '
            'calls validate when graph.nodes.isNotEmpty.',
      );

      // The graph passed to validate must be the populated one.
      expect(
        fakeApi.lastValidatedGraph?.nodes,
        isNotEmpty,
        reason: 'validate must be called with the populated graph.',
      );
    },
  );

  // ── Empty-graph guard ────────────────────────────────────────────────────
  //
  // parseCnlCanonical returns no nodes → canvasProvider stays empty →
  // applyTemplateToWorkspace MUST NOT call validationProvider.validate.
  //
  // EXPECTED OUTCOME: PASS on fixed code.
  testWidgets(
    'applyTemplateToWorkspace — validate is NOT called when canvas is empty '
    '(empty-graph guard)',
    (WidgetTester tester) async {
      final fakeApi = _FakeCanvasApiEmpty();

      final container = ProviderContainer(
        overrides: <Override>[
          canvas_sync.apiClientProvider.overrideWithValue(fakeApi),
          pipelineProvider.overrideWith(
            () => _NoOpPipelineController(const PipelineState()),
          ),
          workspaceBootstrapProvider.overrideWithValue(
            const WorkspaceBootstrap(),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(canvasProvider, (_, _) {});

      late WidgetRef capturedRef;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  capturedRef = ref;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Pre-initialize canvasProvider so its constructor registers the
      // canonicalDocProvider listener BEFORE applyTemplateToWorkspace runs.
      container.read(canvasProvider);

      // Use the empty-spec template — parseCnlCanonical returns no nodes.
      await applyTemplateToWorkspace(capturedRef, _templateEmpty);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Confirm canvas is indeed empty.
      final graph = container.read(canvasProvider).graph;
      expect(
        graph.nodes,
        isEmpty,
        reason:
            'canvasProvider must remain empty so we exercise the validate guard.',
      );

      // CORE ASSERTION: validate must NOT be called on an empty graph.
      expect(
        fakeApi.validateCallCount,
        equals(0),
        reason:
            'Property 1 (Task 4.4): validationProvider.validate MUST NOT be '
            'called when the canvas graph is empty after applyTemplateToWorkspace. '
            'The guard `if (graph.nodes.isNotEmpty)` prevents spurious calls.',
      );
    },
  );
}
