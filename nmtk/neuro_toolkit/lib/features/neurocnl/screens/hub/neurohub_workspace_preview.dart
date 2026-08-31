import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/workspace_file.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart';

enum NeurohubPreviewTab { model, train, evaluate }

class NeurohubWorkspacePreviewData {
  const NeurohubWorkspacePreviewData({
    required this.model,
    required this.pipelinePhases,
  });

  final CanvasGraph model;
  final PipelinePhases pipelinePhases;

  factory NeurohubWorkspacePreviewData.fromPayload(
    Map<String, dynamic> payload,
  ) {
    final normalized = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(payload)) as Map,
    );
    final workspaceJson = normalized['workspace'];
    if (workspaceJson is! Map) {
      throw const FormatException('Workspace preview is unavailable.');
    }
    final workspace = WorkspaceState.fromJson(
      Map<String, dynamic>.from(workspaceJson),
    );
    final projection = workspace.activeFile?.canonicalDocument?.canvas;
    var graph = projection == null
        ? CanvasGraph(nodes: const [], edges: const [], metadata: const {})
        : canvasGraphFromCanonical(
            projection,
            currentGraph: CanvasGraph(
              nodes: const [],
              edges: const [],
              metadata: const {},
            ),
          );

    final canvasJson = normalized['canvas'];
    if (canvasJson is Map) {
      final nodeLayout = canvasJson['nodeLayout'];
      if (nodeLayout is Map) {
        graph = graph.copyWith(
          nodes: <CanvasNode>[
            for (final node in graph.nodes)
              if (nodeLayout[node.id] case final Map<dynamic, dynamic> layout)
                node.copyWith(
                  position: <double>[
                    (layout['x'] as num?)?.toDouble() ?? node.position[0],
                    (layout['y'] as num?)?.toDouble() ?? node.position[1],
                  ],
                  width: (layout['width'] as num?)?.toDouble() ?? node.width,
                  height: (layout['height'] as num?)?.toDouble() ?? node.height,
                  isVisible: layout['isVisible'] as bool? ?? node.isVisible,
                )
              else
                node,
          ],
        );
      }
    }

    PipelinePhases phases = const PipelinePhases();
    if (canvasJson is Map && canvasJson['pipelinePhases'] is Map) {
      phases = PipelinePhases.fromJson(
        Map<String, dynamic>.from(canvasJson['pipelinePhases'] as Map),
      );
    }
    return NeurohubWorkspacePreviewData(model: graph, pipelinePhases: phases);
  }
}

class NeurohubWorkspacePreview extends StatefulWidget {
  const NeurohubWorkspacePreview({
    super.key,
    required this.payload,
    this.compact = false,
  });

  final Map<String, dynamic> payload;
  final bool compact;

  @override
  State<NeurohubWorkspacePreview> createState() =>
      _NeurohubWorkspacePreviewState();
}

class _NeurohubWorkspacePreviewState extends State<NeurohubWorkspacePreview> {
  NeurohubPreviewTab _tab = NeurohubPreviewTab.model;

  @override
  Widget build(BuildContext context) {
    NeurohubWorkspacePreviewData data;
    try {
      data = NeurohubWorkspacePreviewData.fromPayload(widget.payload);
    } on Object {
      return const NmtkEmptyState(
        title: 'Preview unavailable',
        message:
            'This workspace can still be opened, but its canvas preview could not be read.',
        icon: ZetaIcons.warning,
        tone: NmtkTone.warning,
      );
    }
    final scene = switch (_tab) {
      NeurohubPreviewTab.model => _PreviewScene.fromModel(data.model),
      NeurohubPreviewTab.train => _PreviewScene.fromPipeline(
        data.pipelinePhases.train,
      ),
      NeurohubPreviewTab.evaluate => _PreviewScene.fromPipeline(
        data.pipelinePhases.eval,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ZetaSegmentedControl<NeurohubPreviewTab>(
          semanticLabel: 'Workspace preview canvas',
          selected: _tab,
          segments: const <ZetaButtonSegment<NeurohubPreviewTab>>[
            ZetaButtonSegment(
              value: NeurohubPreviewTab.model,
              child: Text('Model'),
            ),
            ZetaButtonSegment(
              value: NeurohubPreviewTab.train,
              child: Text('Train'),
            ),
            ZetaButtonSegment(
              value: NeurohubPreviewTab.evaluate,
              child: Text('Evaluate'),
            ),
          ],
          onChanged: (tab) => setState(() => _tab = tab),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: NmtkShellTokens.of(context).utilityPanelBackground,
              border: Border.all(
                color: NmtkShellTokens.of(context).subtleBorder,
              ),
              borderRadius: BorderRadius.circular(
                NmtkShellTokens.of(context).radiusLg,
              ),
            ),
            child: scene.nodes.isEmpty
                ? const NmtkEmptyState(
                    title: 'Nothing on this canvas',
                    message:
                        'This workspace does not contain nodes for this stage yet.',
                    icon: ZetaIcons.layers,
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(
                      NmtkShellTokens.of(context).radiusLg,
                    ),
                    child: InteractiveViewer(
                      key: const Key('neurohub-read-only-canvas'),
                      minScale: 0.35,
                      maxScale: 3,
                      boundaryMargin: const EdgeInsets.all(240),
                      constrained: false,
                      child: SizedBox(
                        width: math.max(
                          scene.width,
                          widget.compact ? 640 : 960,
                        ),
                        height: math.max(
                          scene.height,
                          widget.compact ? 360 : 520,
                        ),
                        child: CustomPaint(
                          painter: _PreviewScenePainter(
                            scene: scene,
                            nodeColor: Zeta.of(context).colors.mainPrimary,
                            edgeColor: NmtkShellTokens.of(context).chromeBorder,
                            textColor: Zeta.of(context).colors.mainInverse,
                            nodeRadius: NmtkShellTokens.of(context).radiusMd,
                            labelStyle: Zeta.of(context).textStyles.labelMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _PreviewNode {
  const _PreviewNode({
    required this.id,
    required this.label,
    required this.rect,
  });

  final String id;
  final String label;
  final Rect rect;
}

class _PreviewEdge {
  const _PreviewEdge({required this.source, required this.target});

  final String source;
  final String target;
}

class _PreviewScene {
  const _PreviewScene({
    required this.nodes,
    required this.edges,
    required this.width,
    required this.height,
  });

  factory _PreviewScene.fromModel(CanvasGraph graph) {
    final visible = graph.nodes.where((node) => node.isVisible).toList();
    final nodes = <_PreviewNode>[
      for (final node in visible)
        _PreviewNode(
          id: node.id,
          label: node.label ?? node.componentId,
          rect: Rect.fromLTWH(
            node.position[0] + 80,
            node.position[1] + 80,
            node.width,
            node.height,
          ),
        ),
    ];
    return _PreviewScene.fromNodesAndEdges(nodes, <_PreviewEdge>[
      for (final edge in graph.edges)
        _PreviewEdge(source: edge.sourceNodeId, target: edge.targetNodeId),
    ]);
  }

  factory _PreviewScene.fromPipeline(PipelineDAG dag) {
    final nodes = <_PreviewNode>[
      for (final node in dag.nodes)
        _PreviewNode(
          id: node.id,
          label: node.type.label,
          rect: Rect.fromLTWH(
            node.x + 80,
            node.y + 80,
            kPipelineDagNodeWidth,
            pipelineDagNodeHeightFor(node),
          ),
        ),
    ];
    return _PreviewScene.fromNodesAndEdges(nodes, <_PreviewEdge>[
      for (final edge in dag.edges)
        _PreviewEdge(source: edge.sourceNodeId, target: edge.targetNodeId),
    ]);
  }

  factory _PreviewScene.fromNodesAndEdges(
    List<_PreviewNode> nodes,
    List<_PreviewEdge> edges,
  ) {
    final width = nodes.isEmpty
        ? 0.0
        : nodes.map((node) => node.rect.right).reduce(math.max) + 80;
    final height = nodes.isEmpty
        ? 0.0
        : nodes.map((node) => node.rect.bottom).reduce(math.max) + 80;
    return _PreviewScene(
      nodes: nodes,
      edges: edges,
      width: width,
      height: height,
    );
  }

  final List<_PreviewNode> nodes;
  final List<_PreviewEdge> edges;
  final double width;
  final double height;
}

class _PreviewScenePainter extends CustomPainter {
  const _PreviewScenePainter({
    required this.scene,
    required this.nodeColor,
    required this.edgeColor,
    required this.textColor,
    required this.nodeRadius,
    required this.labelStyle,
  });

  final _PreviewScene scene;
  final Color nodeColor;
  final Color edgeColor;
  final Color textColor;
  final double nodeRadius;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final centers = <String, Offset>{
      for (final node in scene.nodes) node.id: node.rect.center,
    };
    final edgePaint = Paint()
      ..color = edgeColor
      ..strokeWidth = 2;
    for (final edge in scene.edges) {
      final source = centers[edge.source];
      final target = centers[edge.target];
      if (source != null && target != null) {
        canvas.drawLine(source, target, edgePaint);
      }
    }
    for (final node in scene.nodes) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(node.rect, Radius.circular(nodeRadius)),
        Paint()..color = nodeColor,
      );
      final text = TextPainter(
        text: TextSpan(
          text: node.label,
          style: labelStyle.copyWith(color: textColor),
        ),
        maxLines: 2,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: node.rect.width - 24);
      text.paint(
        canvas,
        Offset(
          node.rect.left + 12,
          node.rect.top + (node.rect.height - text.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewScenePainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.nodeColor != nodeColor ||
        oldDelegate.edgeColor != edgeColor ||
        oldDelegate.textColor != textColor ||
        oldDelegate.nodeRadius != nodeRadius ||
        oldDelegate.labelStyle != labelStyle;
  }
}
