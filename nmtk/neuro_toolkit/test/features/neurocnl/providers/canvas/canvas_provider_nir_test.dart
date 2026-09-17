import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('autoLayoutGraph tiers NIR nodes left-to-right', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(canvasProvider.notifier)
        .setGraph(
          CanvasGraph(
            nodes: <CanvasNode>[
              CanvasNode(
                id: 'input',
                componentId: 'input_node',
                nirType: 'nir.Input',
                parameters: const <String, dynamic>{'size': 1},
                position: const <double>[500.0, 500.0],
              ),
              CanvasNode(
                id: 'lif',
                componentId: 'lif_population',
                nirType: 'nir.LIF',
                parameters: const <String, dynamic>{'n_neurons': 1},
                position: const <double>[0.0, 0.0],
              ),
              CanvasNode(
                id: 'output',
                componentId: 'output_node',
                nirType: 'nir.Output',
                parameters: const <String, dynamic>{'size': 1},
                position: const <double>[100.0, 100.0],
              ),
            ],
            edges: <CanvasEdge>[
              CanvasEdge(
                id: 'edge_0',
                sourceNodeId: 'input',
                sourcePort: 'out',
                targetNodeId: 'lif',
                targetPort: 'in',
                parameters: <String, dynamic>{},
              ),
              CanvasEdge(
                id: 'edge_1',
                sourceNodeId: 'lif',
                sourcePort: 'out',
                targetNodeId: 'output',
                targetPort: 'in',
                parameters: <String, dynamic>{},
              ),
            ],
            metadata: const <String, dynamic>{'graph_kind': 'nir'},
          ),
        );

    container.read(canvasProvider.notifier).autoLayoutGraph();

    final CanvasGraph graph = container.read(canvasProvider).graph;
    final CanvasNode input = graph.nodes.firstWhere(
      (CanvasNode node) => node.id == 'input',
    );
    final CanvasNode lif = graph.nodes.firstWhere(
      (CanvasNode node) => node.id == 'lif',
    );
    final CanvasNode output = graph.nodes.firstWhere(
      (CanvasNode node) => node.id == 'output',
    );

    expect(input.position[0], lessThan(lif.position[0]));
    expect(lif.position[0], lessThan(output.position[0]));
  });

  test(
    'custom replacement preserves instance data, edges, and base NIR type',
    () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final original = CanvasNode(
        id: 'lif',
        componentId: 'lif_population',
        nirType: 'nir.CubaLIF',
        label: 'Selected neuron',
        parameters: const <String, dynamic>{'tau_mem': 0.03},
        position: const <double>[120, 240],
        width: 220,
        height: 140,
      );
      final edge = CanvasEdge(
        id: 'edge',
        sourceNodeId: 'input',
        sourcePort: 'out',
        targetNodeId: 'lif',
        targetPort: 'in',
        parameters: const <String, dynamic>{'weight': 2.0},
      );
      container
          .read(canvasProvider.notifier)
          .setGraph(
            CanvasGraph(
              nodes: <CanvasNode>[
                CanvasNode(
                  id: 'input',
                  componentId: 'input_node',
                  nirType: 'nir.Input',
                  parameters: const <String, dynamic>{},
                  position: const <double>[0, 0],
                ),
                original,
              ],
              edges: <CanvasEdge>[edge],
              metadata: const <String, dynamic>{},
            ),
          );

      final before = container
          .read(canvasProvider)
          .graph
          .nodes
          .firstWhere((CanvasNode node) => node.id == 'lif');
      container
          .read(canvasProvider.notifier)
          .replaceNodeComponent(
            'lif',
            'custom_selected_neuron_a1b2c3d4',
            baseNirType: 'nir.CubaLIF',
          );

      final graph = container.read(canvasProvider).graph;
      final replaced = graph.nodes.firstWhere(
        (CanvasNode node) => node.id == 'lif',
      );
      expect(replaced.componentId, 'custom_selected_neuron_a1b2c3d4');
      expect(replaced.nirType, 'nir.CubaLIF');
      expect(replaced.label, before.label);
      expect(replaced.parameters, before.parameters);
      expect(replaced.position, before.position);
      expect(replaced.width, before.width);
      expect(replaced.height, before.height);
      expect(replaced.metadata['is_custom'], isTrue);
      expect(graph.edges.single.toJson(), edge.toJson());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    },
  );
}
