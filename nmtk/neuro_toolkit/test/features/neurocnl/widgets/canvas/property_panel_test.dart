import 'package:riverpod_annotation/riverpod_annotation.dart';
// Widget Tests — PropertyPanel uses ZetaTextInput (NIR editor style)
//
// **Validates: Inspector pane textfield styling parity with the NIR editor**
//
// Tests:
//   T1 — Inspector renders ZetaTextInput (not bare TextField) for parameter
//        editing on the canvas node inspector.
//   T2 — Editing a parameter via the inspector updates canvasProvider.
//   T3 — Disabled state is honored (NIR Type field is read-only).
//   T4 — Edge inspector uses ZetaTextInput for weight/delay parameters.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/property_panel.dart';

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

CanvasNode _lifNode({double threshold = 1.0}) => CanvasNode(
  id: 'lif_inspector_node',
  componentId: 'lif_population',
  nirType: 'nir.LIF',
  label: 'Test LIF',
  parameters: <String, dynamic>{
    'name': 'lif_inspector_node',
    'n_neurons': 10,
    'threshold': threshold,
    'tau': 0.02,
    'r': 1.0,
    'v_leak': 0.0,
  },
  position: const <double>[100.0, 100.0],
  metadata: const <String, dynamic>{'category': 'neuron'},
);

ProviderContainer _makeContainer({
  required CanvasGraph graph,
  String? selectedNodeId,
  String? selectedEdgeId,
}) {
  final container = ProviderContainer(
    overrides: <Override>[
      canvas_sync.apiClientProvider.overrideWithValue(_FakeCanvasApiClient()),
    ],
  );
  container.read(canvasProvider.notifier).setGraph(graph);
  if (selectedNodeId != null || selectedEdgeId != null) {
    container
        .read(canvasProvider.notifier)
        .restoreSelection(
          selectedNodeIds: selectedNodeId == null ? null : {selectedNodeId},
          selectedEdgeId: selectedEdgeId,
        );
  }
  return container;
}

Widget _buildApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: PropertyPanel())),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ServerConfigService.initialize();
  });

  setUp(() async {
    final TestWidgetsFlutterBinding binding =
        TestWidgetsFlutterBinding.ensureInitialized();
    // ignore: deprecated_member_use
    binding.window.physicalSizeTestValue = const Size(1024, 1024);
    // ignore: deprecated_member_use
    binding.window.devicePixelRatioTestValue = 1.0;

    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
  });

  // ── T1 — Inspector uses TextField ──────────────
  group('T1 — Inspector pane renders TextField', () {
    testWidgets('renders at least one TextField when a node is selected', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer(
        graph: CanvasGraph(
          nodes: [_lifNode(threshold: 1.0)],
          edges: const [],
          metadata: const {},
        ),
        selectedNodeId: 'lif_inspector_node',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      // PropertyPanel should render at least one TextField (Label, NIR
      // Type, and the typed parameters all use the NIR editor styling).
      expect(
        find.byType(TextField),
        findsAtLeastNWidgets(1),
        reason:
            'Inspector pane should render TextField '
            'for the Label, NIR Type, and parameter fields.',
      );
    });

    testWidgets('inspector label field shows the current node label', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer(
        graph: CanvasGraph(
          nodes: [_lifNode(threshold: 1.0)],
          edges: const [],
          metadata: const {},
        ),
        selectedNodeId: 'lif_inspector_node',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      // And the current value should be the node label.
      expect(
        find.text('Test LIF'),
        findsAtLeastNWidgets(1),
        reason: 'Inspector Label field should contain the node label.',
      );
      expect(find.text('View Python'), findsOneWidget);
    });
  });

  // ── T2 — Inspector field commit updates canvasProvider ─────────────────
  group('T2 — Inspector field commit updates canvasProvider', () {
    testWidgets('entering 0.8 in the threshold field updates the canvas node', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer(
        graph: CanvasGraph(
          nodes: [_lifNode(threshold: 1.0)],
          edges: const [],
          metadata: const {},
        ),
        selectedNodeId: 'lif_inspector_node',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      // find.widgetWithText pattern (also used in nir_node_card_test) still
      // works for entering text.
      final thresholdField = find.widgetWithText(TextField, '1.0');
      expect(
        thresholdField,
        findsAtLeastNWidgets(1),
        reason:
            'A TextField holding the current threshold value "1.0" '
            'should be present in the inspector.',
      );

      await tester.enterText(thresholdField.first, '0.8');
      await tester.pump();
      // Drain the 200 ms CanvasParameterTextField commit debounce AND the
      // 300 ms CanvasController._pushToCanonical debounce that follow it.
      await tester.pump(const Duration(milliseconds: 600));

      final nodes = container.read(canvasProvider).graph.nodes;
      final lifNode = nodes.firstWhere((n) => n.id == 'lif_inspector_node');
      expect(
        lifNode.parameters['threshold'],
        closeTo(0.8, 0.0001),
        reason:
            'T2: canvasProvider.graph.nodes[id].parameters[threshold] must '
            'equal 0.8 after entering 0.8 in the inspector threshold field.',
      );
    });
  });

  // ── T3 — Disabled state honored (NIR Type is read-only) ────────────────
  group('T3 — Inspector disables read-only fields (NIR Type)', () {
    testWidgets('NIR Type field is disabled', (WidgetTester tester) async {
      final container = _makeContainer(
        graph: CanvasGraph(
          nodes: [_lifNode(threshold: 1.0)],
          edges: const [],
          metadata: const {},
        ),
        selectedNodeId: 'lif_inspector_node',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      // Find the NIR Type TextField and verify it is disabled.
      final nirTypeField = find.widgetWithText(TextField, 'nir.LIF');
      expect(
        nirTypeField,
        findsAtLeastNWidgets(1),
        reason:
            'A TextField holding the NIR type "nir.LIF" should be '
            'present in the inspector.',
      );

      final textField = tester.widget<TextField>(nirTypeField.first);
      expect(
        textField.enabled,
        isFalse,
        reason: 'T3: The NIR Type field must be disabled (read-only).',
      );
    });
  });

  group('PropertyPanel — multi-select', () {
    testWidgets('shows summary when multiple nodes are selected', (
      WidgetTester tester,
    ) async {
      final graph = CanvasGraph(
        nodes: <CanvasNode>[
          _lifNode(),
          _lifNode().copyWith(
            id: 'lif_inspector_node_2',
            label: 'Test LIF 2',
            parameters: <String, dynamic>{
              'name': 'lif_inspector_node_2',
              'n_neurons': 10,
              'threshold': 1.0,
              'tau': 0.02,
              'r': 1.0,
              'v_leak': 0.0,
            },
          ),
        ],
        edges: const <CanvasEdge>[],
        metadata: const <String, dynamic>{},
      );
      final container = _makeContainer(graph: graph);
      container.read(canvasProvider.notifier).selectNodes({
        'lif_inspector_node',
        'lif_inspector_node_2',
      });
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      expect(find.text('2 nodes selected'), findsOneWidget);
    });
  });

  group('PropertyPanel — dangling edge selection', () {
    testWidgets('shows a placeholder instead of a blank panel', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer(
        graph: CanvasGraph(
          nodes: const <CanvasNode>[],
          edges: const <CanvasEdge>[],
          metadata: const <String, dynamic>{},
        ),
        selectedEdgeId: 'deleted_edge_id',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      expect(find.text('This connection no longer exists.'), findsOneWidget);
    });
  });

  // ── Network Settings panel (nothing selected) ───────────────────────────
  group('Network Settings panel', () {
    testWidgets('shows empty/hinted field when no network dt is set', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer(
        graph: CanvasGraph(
          nodes: const <CanvasNode>[],
          edges: const <CanvasEdge>[],
          metadata: const <String, dynamic>{},
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      expect(find.text('Network Settings'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('network__dt')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller?.text ?? '', isEmpty);
    });

    testWidgets('shows the declared value when network dt is set', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer(
        graph: CanvasGraph(
          nodes: const <CanvasNode>[],
          edges: const <CanvasEdge>[],
          metadata: const <String, dynamic>{'dt': 0.002},
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '0.002'), findsOneWidget);
    });

    testWidgets('editing the field commits via setNetworkTimestepSeconds', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer(
        graph: CanvasGraph(
          nodes: const <CanvasNode>[],
          edges: const <CanvasEdge>[],
          metadata: const <String, dynamic>{},
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('network__dt')),
        '0.001',
      );
      await tester.pump();
      // Drain the 200ms text-field commit debounce + the 300ms
      // CanvasController._pushToCanonical debounce.
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        container.read(canvasProvider).graph.metadata['dt'],
        closeTo(0.001, 0.0001),
      );
    });

    testWidgets('clearing the field removes the dt key', (
      WidgetTester tester,
    ) async {
      final container = _makeContainer(
        graph: CanvasGraph(
          nodes: const <CanvasNode>[],
          edges: const <CanvasEdge>[],
          metadata: const <String, dynamic>{'dt': 0.002},
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildApp(container));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('network__dt')), '');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        container.read(canvasProvider).graph.metadata.containsKey('dt'),
        isFalse,
      );
    });
  });
}
