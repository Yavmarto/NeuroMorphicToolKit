import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    hide CanvasNode;
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/pipeline_phase_canvas.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCanvasApiClient extends ApiClient {
  _FakeCanvasApiClient() : super(baseUrl: 'http://localhost:0');

  @override
  Future<ParseCnlResponse> canvasToCanonical(CanvasGraph graph) async =>
      const ParseCnlResponse(document: CanonicalEditorDocument(irJson: {}));

  @override
  Future<ValidationResult> validateGraph(CanvasGraph graph) async =>
      ValidationResult(valid: true, errors: const []);
}

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

  testWidgets('a visible pipeline node remains draggable across the viewport', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(2048, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ProviderContainer container = ProviderContainer(
      overrides: [
        canvas_sync.apiClientProvider.overrideWithValue(_FakeCanvasApiClient()),
      ],
    );
    addTearDown(container.dispose);

    const String nodeId = 'far_right_node';
    container
        .read(canvasProvider.notifier)
        .addPipelineDagNode(
          PipelinePhaseId.train,
          const PipelineDagNode(
            id: nodeId,
            type: PipelineDagNodeType.forwardPass,
            x: 4500,
            y: 0,
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: PipelinePhaseCanvas(phase: PipelinePhaseId.train),
          ),
        ),
      ),
    );
    await tester.pump();

    container.read(canvasProvider.notifier).requestWorkspaceRestoreFocus();
    await tester.pump();
    await tester.pumpAndSettle();

    final Finder node = find.byKey(const ValueKey<String>('pnode_$nodeId'));
    expect(node, findsOneWidget);
    final Offset visibleCenter = tester.getCenter(node);
    expect(visibleCenter.dx, inInclusiveRange(0, 2048));
    expect(visibleCenter.dy, inInclusiveRange(0, 1100));

    final double before = container
        .read(canvasProvider)
        .pipelinePhases
        .dagFor(PipelinePhaseId.train)
        .nodes
        .single
        .x;

    final TestGesture gesture = await tester.startGesture(visibleCenter);
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-240, 0));
    await tester.pump();

    final double duringDrag = container
        .read(canvasProvider)
        .pipelinePhases
        .dagFor(PipelinePhaseId.train)
        .nodes
        .single
        .x;
    expect(duringDrag, lessThan(before));

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
