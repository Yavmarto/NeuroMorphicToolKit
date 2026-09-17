import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/component.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/custom_pipeline_node.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';

void main() {
  ComponentBlock customAdam({List<String> canvases = const ['training']}) =>
      ComponentBlock(
        id: 'custom_adam_12345678',
        name: 'My Adam',
        category: 'optimiser',
        description: '',
        icon: 'custom_node',
        parameters: [
          ParameterDef(
            name: 'lr',
            label: 'Learning Rate',
            description: '',
            type: 'float',
            defaultValue: 0.004,
          ),
        ],
        ports: [],
        cnlTemplate: '',
        isCustom: true,
        basePipelineType: 'adamOptimiser',
        canvasContexts: canvases,
        supportedFrameworks: const ['snntorch_sim'],
      );

  test('training palette includes reusable custom pipeline nodes', () {
    final items = pipelinePaletteItems(
      phase: PipelinePhaseId.train,
      platforms: {'snntorch_sim'},
      components: [customAdam()],
    );
    final custom = items.firstWhere(
      (item) => item.id == 'custom_adam_12345678',
    );

    expect(custom.type, PipelineDagNodeType.adamOptimiser);
    expect(custom.label, 'My Adam');
    expect(custom.defaultParameters['lr'], 0.004);
  });

  test('custom nodes are filtered to their declared canvas', () {
    final items = pipelinePaletteItems(
      phase: PipelinePhaseId.eval,
      platforms: {'snntorch_sim'},
      components: [customAdam()],
    );

    expect(items.any((item) => item.id == 'custom_adam_12345678'), isFalse);
  });
}
