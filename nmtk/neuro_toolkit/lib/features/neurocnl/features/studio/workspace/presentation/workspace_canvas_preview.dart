import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/nir_types_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/canvas/presentation/preview_graph.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/canvas/presentation/workspace_preview_painter.dart';

/// Workspace-owned summary of the current model and pipeline canvases.
class WorkspaceCanvasPreview extends ConsumerWidget {
  const WorkspaceCanvasPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canvas = ref.watch(canvasProvider);
    final nirTypeMap = ref.watch(nirNodeTypeMapProvider);
    final architecture = PreviewGraph.fromArchitecture(
      context,
      canvas.graph,
      nirTypeMap,
    );
    final train = PreviewGraph.fromPipeline(
      canvas.pipelinePhases.dagFor(PipelinePhaseId.train),
    );
    final evaluation = PreviewGraph.fromPipeline(
      canvas.pipelinePhases.dagFor(PipelinePhaseId.eval),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Workspace preview',
          style: Zeta.of(
            context,
          ).textStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Expanded(child: _previewRow(context, 'Model canvas', architecture)),
        const SizedBox(height: 12),
        Expanded(child: _previewRow(context, 'Training canvas', train)),
        const SizedBox(height: 12),
        Expanded(child: _previewRow(context, 'Evaluation canvas', evaluation)),
      ],
    );
  }

  Widget _previewRow(BuildContext context, String label, PreviewGraph graph) {
    final tokens = NmtkShellTokens.of(context);
    final colors = Zeta.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.utilityPanelBackground,
        border: Border.all(color: tokens.subtleBorder),
        borderRadius: BorderRadius.circular(tokens.radiusLg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomPaint(
                painter: WorkspacePreviewPainter(
                  graph: graph,
                  edgeColor: tokens.chromeBorder,
                ),
              ),
            ),
            const SizedBox(width: 20),
            SizedBox(
              width: 112,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: Zeta.of(context).textStyles.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    '${graph.nodes.length} nodes',
                    style: Zeta.of(
                      context,
                    ).textStyles.bodySmall.copyWith(color: colors.mainSubtle),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${graph.edges.length} edges',
                    style: Zeta.of(
                      context,
                    ).textStyles.bodySmall.copyWith(color: colors.mainSubtle),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
