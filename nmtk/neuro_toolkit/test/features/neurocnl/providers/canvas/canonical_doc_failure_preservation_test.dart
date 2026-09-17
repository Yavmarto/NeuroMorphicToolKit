// A failed canvas→CNL push must not blank the CNL panel.
//
// Bug: CanonicalDocController's three updateFrom* methods each opened with a
// bare `state = const AsyncLoading()`. A bare AsyncLoading carries no value,
// and AsyncError.copyWithPrevious forwards that null through — so ONE failed
// `canvas-to-canonical` call left canonicalDocProvider.value == null for good.
// Downstream that meant:
//   - spec_provider.dart reads `doc.value?.cnlText ?? ''` → the CNL editor went
//     blank and never refilled;
//   - notebook_generate_service saw an empty spec → "No architecture to
//     generate from".
// Both halves of "editing the canvas does not update the CNL and does not get
// generated" came from that one line. The server returns a blanket 422 for any
// importer exception, so a single CNL-unrenderable node poisoned every
// subsequent edit — and the only handler was a debugPrint, so it was silent.
//
// Fix: `_loadingPreservingDocument` (copyWithPrevious), so the resolved document
// survives both the in-flight phase and the AsyncError that follows a failure.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical_doc;
import 'package:neuro_toolkit/features/neurocnl/models/workspace_file.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

/// _publishDocument kicks off the real PipelineController.runParseAndValidate,
/// whose async work outlives the container in a unit test. Stub it out — this
/// suite is about document preservation, not the pipeline.
class _NoOpPipelineController extends PipelineController {
  @override
  PipelineState build() => const PipelineState();

  @override
  Future<void> runParseAndValidate(
    String spec, {
    String? backendOverride,
  }) async {}

  @override
  Future<void> runGenerateAndSimulate(
    String spec, {
    double duration = 1.0,
  }) async {}

  @override
  void hydrateCachedResultsForFile(WorkspaceFile? file) {}

  @override
  void cancelSimulation() {}

  @override
  void reset() {}
}

const _goodCnl = 'The retina population MUST encode input using 8 neurons';

/// Returns a good document until [failFrom] calls have succeeded, then throws
/// the same 422-shaped CanvasSyncException the real backend produces.
class _FlakyApiClient extends ApiClient {
  _FlakyApiClient({required this.failAfter})
    : super(baseUrl: 'http://localhost:0');

  final int failAfter;
  int canvasToCanonicalCalls = 0;

  @override
  Future<ValidationResult> validateGraph(CanvasGraph graph) async =>
      ValidationResult(valid: true, errors: const []);

  @override
  Future<String> generateCnl(CanvasGraph graph) async => _goodCnl;

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

  @override
  Future<canonical_doc.ParseCnlResponse> canvasToCanonical(
    CanvasGraph graph,
  ) async {
    canvasToCanonicalCalls++;
    if (canvasToCanonicalCalls > failAfter) {
      throw CanvasSyncException(
        message: 'Unsupported node type nir.Linear',
        statusCode: 422,
      );
    }
    return const canonical_doc.ParseCnlResponse(
      document: canonical_doc.CanonicalEditorDocument(
        irJson: {},
        cnlText: _goodCnl,
      ),
      diagnostics: [],
    );
  }
}

CanvasNode _node(String id) => CanvasNode(
  id: id,
  componentId: 'lif_population',
  nirType: 'nir.LIF',
  label: id,
  parameters: <String, dynamic>{'name': id, 'n_neurons': 8, 'threshold': 1.0},
  position: const <double>[0, 0],
  metadata: const <String, dynamic>{'category': 'neuron'},
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
  });

  group('a failed canvas→CNL push preserves the last good document', () {
    test('specTextProvider keeps the previous CNL instead of blanking', () async {
      final api = _FlakyApiClient(failAfter: 1);
      final container = ProviderContainer(
        overrides: [
          canvas_sync.apiClientProvider.overrideWithValue(api),
          pipelineProvider.overrideWith(_NoOpPipelineController.new),
        ],
      );
      addTearDown(container.dispose);
      // Keep the derived providers alive so they recompute as state changes.
      addTearDown(container.listen(specTextProvider, (_, _) {}).close);

      final notifier = container.read(canvasProvider.notifier);
      notifier.setGraph(
        CanvasGraph(
          nodes: <CanvasNode>[_node('a')],
          edges: const <CanvasEdge>[],
          metadata: const <String, dynamic>{},
        ),
      );

      // Captured once and reused for both pushes. Re-reading it would hand the
      // second push an empty graph: the fake document carries no canvas
      // projection, so publishing it makes the canonical→canvas mirror take its
      // empty-projection branch, and updateFromCanvas early-returns on
      // `graph.nodes.isEmpty` before it ever reaches the client.
      final graph = container.read(canvasProvider).graph;
      final docNotifier = container.read(
        canonicalDocControllerProvider.notifier,
      );

      // First push succeeds — this is the "last good" document.
      await docNotifier.updateFromCanvas(graph);
      expect(container.read(specTextProvider), _goodCnl);

      // Second push fails with the backend's 422.
      await docNotifier.updateFromCanvas(graph);

      expect(
        api.canvasToCanonicalCalls,
        greaterThanOrEqualTo(2),
        reason: 'the second push must have reached the (failing) client',
      );
      final state = container.read(canonicalDocControllerProvider);
      expect(state.hasError, isTrue, reason: 'the failure must be observable');

      // The whole point: value survives the error, so the editor still has text
      // and codegen still has a spec.
      expect(
        state.value?.cnlText,
        _goodCnl,
        reason: 'AsyncError must carry the previous document forward',
      );
      expect(
        container.read(specTextProvider),
        _goodCnl,
        reason: 'a failed push must not blank the CNL panel',
      );
    });

    test('the in-flight state also keeps the document readable', () async {
      final api = _FlakyApiClient(failAfter: 99);
      final container = ProviderContainer(
        overrides: [
          canvas_sync.apiClientProvider.overrideWithValue(api),
          pipelineProvider.overrideWith(_NoOpPipelineController.new),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(container.listen(specTextProvider, (_, _) {}).close);

      final notifier = container.read(canvasProvider.notifier);
      notifier.setGraph(
        CanvasGraph(
          nodes: <CanvasNode>[_node('a')],
          edges: const <CanvasEdge>[],
          metadata: const <String, dynamic>{},
        ),
      );
      final docNotifier = container.read(
        canonicalDocControllerProvider.notifier,
      );
      await docNotifier.updateFromCanvas(container.read(canvasProvider).graph);
      expect(container.read(specTextProvider), _goodCnl);

      // Start a second push but do not await it — mid-flight the state is
      // AsyncLoading, which previously read as "no document".
      final pending = docNotifier.updateFromCanvas(
        container.read(canvasProvider).graph,
      );
      // Asserting the observable behaviour, not Riverpod's isLoading flag:
      // whatever the in-flight representation is, the document must stay
      // readable through it.
      expect(
        container.read(canonicalDocControllerProvider).value?.cnlText,
        _goodCnl,
        reason: 'the in-flight state must still carry the document',
      );
      expect(
        container.read(specTextProvider),
        _goodCnl,
        reason: 'the CNL panel must not blank while a push is in flight',
      );
      await pending;
    });
  });
}
