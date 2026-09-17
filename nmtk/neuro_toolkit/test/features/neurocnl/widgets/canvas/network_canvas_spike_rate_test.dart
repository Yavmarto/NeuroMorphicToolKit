// Widget tests for the canvas node spike-rate highlight: trainingModeProvider
// (canvas-node-id -> rate) drives a colored badge/border on the matching
// node, and stays invisible when the provider is null/empty — the state the
// Architecture tab (which never writes it) is always in.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    hide CanvasNode, CanvasEdge;
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/training_mode_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_canvas.dart';

class _FakeCanvasApiClient extends ApiClient {
  _FakeCanvasApiClient() : super(baseUrl: 'http://localhost:0');

  @override
  Future<ParseCnlResponse> canvasToCanonical(CanvasGraph graph) async =>
      const ParseCnlResponse(document: CanonicalEditorDocument(irJson: {}));

  @override
  Future<ValidationResult> validateGraph(CanvasGraph graph) async =>
      ValidationResult(valid: true, errors: const []);
}

const String _nodeId = 'lif_1';

ProviderContainer _makeContainer() {
  final container = ProviderContainer(
    overrides: [
      canvas_sync.apiClientProvider.overrideWithValue(_FakeCanvasApiClient()),
    ],
  );
  container
      .read(canvasProvider.notifier)
      .setGraph(
        CanvasGraph(
          nodes: <CanvasNode>[
            CanvasNode(
              id: _nodeId,
              componentId: 'lif_population',
              nirType: 'nir.LIF',
              label: 'LIF',
              parameters: const <String, dynamic>{'name': 'LIF 1'},
              position: const <double>[400, 300],
              width: 200,
              height: 160,
            ),
          ],
          edges: const <CanvasEdge>[],
          metadata: const <String, dynamic>{},
        ),
      );
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
          body: SizedBox(width: 1200, height: 900, child: NetworkCanvas()),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Drains the debounced canonical-doc push and workspace server-sync timers
/// `setGraph` schedules. Without this the framework's pending-timer
/// invariant fails the test even when every assertion has passed.
Future<void> _flushSchedulerTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
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

  testWidgets('shows no spike-rate badge when trainingModeProvider is null', (
    WidgetTester tester,
  ) async {
    final container = _makeContainer();
    addTearDown(container.dispose);
    await _pumpCanvas(tester, container);

    expect(find.textContaining('%'), findsNothing);

    await _flushSchedulerTimers(tester);
  });

  testWidgets('shows the resolved rate as a badge on the matching node', (
    WidgetTester tester,
  ) async {
    final container = _makeContainer();
    addTearDown(container.dispose);
    container.read(trainingModeProvider.notifier).setRates({_nodeId: 0.42});
    await _pumpCanvas(tester, container);

    expect(find.text('42%'), findsOneWidget);

    await _flushSchedulerTimers(tester);
  });

  testWidgets('clears the badge when the provider is cleared', (
    WidgetTester tester,
  ) async {
    final container = _makeContainer();
    addTearDown(container.dispose);
    container.read(trainingModeProvider.notifier).setRates({_nodeId: 0.42});
    await _pumpCanvas(tester, container);
    expect(find.text('42%'), findsOneWidget);

    container.read(trainingModeProvider.notifier).clear();
    await tester.pump();

    expect(find.textContaining('%'), findsNothing);

    await _flushSchedulerTimers(tester);
  });
}
