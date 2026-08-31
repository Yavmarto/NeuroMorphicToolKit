import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/nir_node_styles.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_minimap.dart';

/// Render-ready canvas geometry for the workspace overview.
class PreviewGraph {
  const PreviewGraph({required this.nodes, required this.edges});

  factory PreviewGraph.fromArchitecture(
    BuildContext context,
    CanvasGraph graph,
    Map<String, NirNodeType> nirTypeMap,
  ) {
    final centers = <String, Offset>{};
    final nodes = <MinimapNode>[];
    for (final node in graph.nodes) {
      final rect = Rect.fromLTWH(
        node.position[0],
        node.position[1],
        node.width,
        node.height,
      );
      final nodeType = nirTypeMap[node.nirType ?? node.componentId];
      nodes.add(
        MinimapNode(
          rect,
          nodeType != null
              ? nirCategoryColor(context, nodeType.category)
              // Falls back alongside nirCategoryColor, which is itself exempt from
              // the Zeta-only color rule (see nir_node_styles.dart).
              : Colors.grey,
        ),
      );
      centers[node.id] = rect.center;
    }
    return PreviewGraph(
      nodes: nodes,
      edges: [
        for (final edge in graph.edges)
          if (centers[edge.sourceNodeId] case final source?)
            if (centers[edge.targetNodeId] case final target?)
              MinimapEdgeLine(source, target),
      ],
    );
  }

  factory PreviewGraph.fromPipeline(PipelineDAG dag) {
    final centers = <String, Offset>{};
    final nodes = <MinimapNode>[];
    for (final node in dag.nodes) {
      final rect = Rect.fromLTWH(
        node.x,
        node.y,
        kPipelineDagNodeWidth,
        pipelineDagNodeHeightFor(node),
      );
      nodes.add(MinimapNode(rect, pipelineCategoryColor(node.type.category)));
      centers[node.id] = rect.center;
    }
    return PreviewGraph(
      nodes: nodes,
      edges: [
        for (final edge in dag.edges)
          if (centers[edge.sourceNodeId] case final source?)
            if (centers[edge.targetNodeId] case final target?)
              MinimapEdgeLine(source, target),
      ],
    );
  }

  final List<MinimapNode> nodes;
  final List<MinimapEdgeLine> edges;
}
