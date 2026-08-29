import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/models/network_graph.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/network_graph_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
  });

  testWidgets('NetworkGraphView shows placeholder when no graph', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: NetworkGraphView())),
      ),
    );

    expect(
      find.text('Run the model to inspect the compiled graph.'),
      findsOneWidget,
    );
  });

  testWidgets('NetworkGraphView renders graph when data is present', (
    WidgetTester tester,
  ) async {
    const network = NetworkGraph(
      nodes: [
        NetworkNode(
          id: 'n1',
          type: 'ensemble',
          subtype: 'sensory',
          label: 'Ensemble 1',
          params: {'p1': 1.0},
          position: NodePosition(x: 0.5, y: 0.5),
        ),
      ],
      edges: [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pipelineProvider.overrideWith(
            () => _FakePipelineController(
              const PipelineState(
                generateResult: GenerateResult(
                  network: network,
                  cnlDocument: '',
                  nirCode: '',
                ),
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800,
                height: 600,
                child: NetworkGraphView(),
              ),
            ),
          ),
        ),
      ),
    );

    // Should not show placeholder
    expect(
      find.text('Run the model to inspect the compiled graph.'),
      findsNothing,
    );
    expect(find.textContaining('Execution preview only'), findsOneWidget);

    // Should show CustomPaint
    expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));

    // Wait for layout
    await tester.pumpAndSettle();

    // The node is at (0.5, 0.5) of the CustomPaint size.
    // The CustomPaint should be 800x600 (since it's in Expanded, but there's a column)
    // Actually, in the build method, NetworkGraphView returns a Column with Expanded(child: LayoutBuilder(child: CustomPaint)).
    // So CustomPaint should be roughly 800x[some height].

    // Instead of tapping by location which is brittle, let's just check if it renders.
    // We already checked it doesn't show placeholder.
    // Let's check for the node label if it was a widget, but it's not.
  });

  testWidgets(
    'NetworkGraphView condenses simple linear graphs into a summary',
    (WidgetTester tester) async {
      const network = NetworkGraph(
        nodes: [
          NetworkNode(
            id: 'input',
            type: 'input_node',
            subtype: 'stimulus',
            label: 'Input',
            params: {},
            position: NodePosition(x: 0.0, y: 0.0),
          ),
          NetworkNode(
            id: 'hidden',
            type: 'ensemble',
            subtype: 'interneuron',
            label: 'Hidden',
            params: {'n_neurons': 64},
            position: NodePosition(x: 0.5, y: 0.5),
          ),
          NetworkNode(
            id: 'output',
            type: 'ensemble',
            subtype: 'motor',
            label: 'Output',
            params: {'n_neurons': 32},
            position: NodePosition(x: 1.0, y: 1.0),
          ),
        ],
        edges: [
          NetworkEdge(
            id: 'e1',
            source: 'input',
            target: 'hidden',
            isInhibitory: false,
            hasLearningRule: false,
            hasDelay: false,
            params: {},
          ),
          NetworkEdge(
            id: 'e2',
            source: 'hidden',
            target: 'output',
            isInhibitory: false,
            hasLearningRule: false,
            hasDelay: false,
            params: {},
          ),
        ],
      );

      await tester.pumpWidget(_buildTestApp(network: network));
      await tester.pumpAndSettle();

      expect(find.textContaining('Execution preview only'), findsOneWidget);
      expect(find.text('Straight-through generated flow'), findsOneWidget);
      expect(
        find.textContaining('Use the editor number picker to adjust values'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'NetworkGraphView centers nodes with large generated coordinates',
    (WidgetTester tester) async {
      const network = NetworkGraph(
        nodes: [
          NetworkNode(
            id: 'n-large',
            type: 'ensemble',
            subtype: 'sensory',
            label: 'Large Node',
            params: {'p1': 1.0},
            position: NodePosition(x: 5000, y: -3000),
          ),
        ],
        edges: [],
      );

      await tester.pumpWidget(_buildTestApp(network: network));
      await tester.pumpAndSettle();

      await tester.tapAt(tester.getCenter(_graphCanvasFinder()));
      await tester.pumpAndSettle();

      expect(find.text('Large Node'), findsOneWidget);
    },
  );

  testWidgets('NetworkGraphView recomputes layout when viewport size changes', (
    WidgetTester tester,
  ) async {
    const network = NetworkGraph(
      nodes: [
        NetworkNode(
          id: 'n-resize',
          type: 'ensemble',
          subtype: 'sensory',
          label: 'Resize Node',
          params: {'p1': 1.0},
          position: NodePosition(x: 1000, y: 1000),
        ),
      ],
      edges: [],
    );

    final size = ValueNotifier<Size>(const Size(200, 200));

    await tester.pumpWidget(
      _buildTestApp(network: network, sizeListenable: size),
    );
    await tester.pumpAndSettle();

    size.value = const Size(800, 600);
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(_graphCanvasFinder()));
    await tester.pumpAndSettle();

    expect(find.text('Resize Node'), findsOneWidget);
  });
}

Finder _graphCanvasFinder() {
  return find.descendant(
    of: find.byType(GestureDetector),
    matching: find.byType(CustomPaint),
  );
}

Widget _buildTestApp({
  required NetworkGraph network,
  ValueNotifier<Size>? sizeListenable,
}) {
  final content = sizeListenable == null
      ? const SizedBox(width: 800, height: 600, child: NetworkGraphView())
      : ValueListenableBuilder<Size>(
          valueListenable: sizeListenable,
          builder: (context, size, child) {
            return SizedBox(
              width: size.width,
              height: size.height,
              child: child,
            );
          },
          child: const NetworkGraphView(),
        );

  return ProviderScope(
    overrides: [
      pipelineProvider.overrideWith(
        () => _FakePipelineController(
          PipelineState(
            generateResult: GenerateResult(
              network: network,
              cnlDocument: '',
              nirCode: '',
            ),
          ),
        ),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: Center(child: content)),
    ),
  );
}

class _FakePipelineController extends PipelineController {
  _FakePipelineController(this._initial);
  final PipelineState _initial;
  @override
  PipelineState build() => _initial;
}
