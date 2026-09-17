// Widget tests for stylus parity on the pipeline (Train/Eval) canvases.
//
// The stylus lasso and handwriting-to-node used to exist only on the
// Architecture canvas, so the same pen did different things depending on which
// tab was open. Both now come from CanvasStylusMixin; these tests pin that the
// pipeline canvas actually gets them, and that the recognizer still declines
// over ports so drag-to-connect keeps working.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    hide CanvasNode;
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/component.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/component_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/pipeline_phase_canvas.dart';

/// Keeps the fire-and-forget canonical-doc/validation sync off the network.
class _FakeCanvasApiClient extends ApiClient {
  _FakeCanvasApiClient() : super(baseUrl: 'http://localhost:0');

  @override
  Future<ParseCnlResponse> canvasToCanonical(CanvasGraph graph) async =>
      const ParseCnlResponse(document: CanonicalEditorDocument(irJson: {}));

  @override
  Future<ValidationResult> validateGraph(CanvasGraph graph) async =>
      ValidationResult(valid: true, errors: const []);
}

ProviderContainer _makeContainer({List<PipelineDagNode> nodes = const []}) {
  final container = ProviderContainer(
    overrides: [
      canvas_sync.apiClientProvider.overrideWithValue(_FakeCanvasApiClient()),
      componentsProvider.overrideWith((ref) async => const <ComponentBlock>[]),
    ],
  );
  final notifier = container.read(canvasProvider.notifier);
  for (final PipelineDagNode node in nodes) {
    // Added at an explicit position, so no grid-snap reflow moves the cards
    // out from under the coordinates these tests drag over.
    notifier.addPipelineDagNode(PipelinePhaseId.train, node);
  }
  return container;
}

Future<void> _pumpCanvas(
  WidgetTester tester,
  ProviderContainer container,
) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 900,
            child: PipelinePhaseCanvas(phase: PipelinePhaseId.train),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

PipelineDAG _trainDag(ProviderContainer container) =>
    container.read(canvasProvider).pipelinePhases.dagFor(PipelinePhaseId.train);

void main() {
  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
  });

  testWidgets('a stylus drag over empty canvas lasso-selects the nodes under '
      'the rect', (tester) async {
    final container = _makeContainer(
      nodes: const [
        PipelineDagNode(
          id: 'loader',
          type: PipelineDagNodeType.dataLoader,
          x: 300,
          y: 300,
        ),
      ],
    );
    addTearDown(container.dispose);
    await _pumpCanvas(tester, container);

    // Adding a node selects it; start from a clean slate so the assertion
    // below is about the lasso and nothing else.
    container.read(canvasProvider.notifier).clearSelection();
    await tester.pump();
    expect(container.read(canvasProvider).selectedNodeIds, isEmpty);

    // The provider grid-snaps an added node, so the drag is derived from
    // where the card actually landed: start on empty canvas above-left of it
    // and sweep across its top-left corner.
    final Rect card = tester.getRect(
      find.byKey(const ValueKey<String>('pnode_loader')),
    );
    await tester.dragFrom(
      card.topLeft - const Offset(40, 40),
      const Offset(60, 60),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(canvasProvider).selectedNodeIds, {'loader'});
  });

  testWidgets('a short stylus tap on empty canvas opens the handwriting field, '
      'and submitting a node name creates that node', (tester) async {
    final container = _makeContainer();
    addTearDown(container.dispose);
    await _pumpCanvas(tester, container);

    expect(_trainDag(container).nodes, isEmpty);

    final TestGesture gesture = await tester.startGesture(
      const Offset(700, 500),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));

    final Finder handwritingField = find.widgetWithText(
      TextField,
      'Node type…',
    );
    expect(handwritingField, findsOneWidget);

    // Deliberately misspelt: the fuzzy phase of the shared ranking is what
    // makes handwriting-OCR errors recoverable.
    await tester.enterText(handwritingField, 'Data Loder');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 400));

    expect(_trainDag(container).nodes, hasLength(1));
    expect(
      _trainDag(container).nodes.single.type,
      PipelineDagNodeType.dataLoader,
    );
  });

  testWidgets('a stylus drag from an output port still creates a connection '
      '(the empty-canvas recognizer declines over ports)', (tester) async {
    final container = _makeContainer(
      nodes: const [
        PipelineDagNode(
          id: 'loader',
          type: PipelineDagNodeType.dataLoader,
          x: 200,
          y: 200,
        ),
        PipelineDagNode(
          id: 'encoder',
          type: PipelineDagNodeType.spikeEncoder,
          x: 600,
          y: 200,
        ),
      ],
    );
    addTearDown(container.dispose);
    await _pumpCanvas(tester, container);

    final Offset start = tester.getCenter(
      find.byKey(const ValueKey<String>('port_loader_data')),
    );
    final Offset end = tester.getCenter(
      find.byKey(const ValueKey<String>('port_encoder_data')),
    );

    final TestGesture gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.stylus,
    );
    for (int i = 1; i <= 20; i += 1) {
      await gesture.moveTo(Offset.lerp(start, end, i / 20)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_trainDag(container).edges, isNotEmpty);
  });
}
