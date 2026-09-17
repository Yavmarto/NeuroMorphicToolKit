import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/nir_node_styles.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_edge_painting.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_canvas.dart';

class ConnectionPainter extends CustomPainter {
  ConnectionPainter({
    required this.graph,
    required this.nirTypeMap,
    this.connectingFromNodeId,
    this.connectingFromPortId,
    this.currentConnectingPoint,
    this.currentConnectingPressure = 1.0,
    this.selectedEdgeId,
    required this.primaryColor,
    required this.outlineColor,
    this.isVertical = false,
    this.sceneOrigin = Offset.zero,
    required this.badgeAccentColor,
  });

  final CanvasGraph graph;
  final Map<String, NirNodeType> nirTypeMap;
  final String? connectingFromNodeId;
  final String? connectingFromPortId;
  final Offset? currentConnectingPoint;

  /// Latest stylus pressure (0.0-1.0; defaults to 1.0 for non-pressure
  /// devices) sampled while a connection is being dragged. Used only to
  /// scale the width of the uncommitted, in-progress preview wire below.
  final double currentConnectingPressure;
  final String? selectedEdgeId;
  final Color primaryColor;
  final Color outlineColor;
  final bool isVertical;
  final Offset sceneOrigin;

  /// Border/text color for the learning-rule badge, resolved from the
  /// active Zeta theme by the caller (paint() has no BuildContext). Reads as
  /// white-on-colored-circle in both themes -- same `mainInverse` pairing
  /// [TileGridNeuronRenderer] uses for its dark-card popup.
  final Color badgeAccentColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(sceneOrigin.dx, sceneOrigin.dy);
    for (final CanvasEdge edge in graph.edges) {
      final bool isSelected = edge.id == selectedEdgeId;
      final double strokeWeight =
          (edge.parameters['strokeWeight'] as num?)?.toDouble() ?? 1.0;

      final Offset? source = _getPortPosition(
        edge.sourceNodeId,
        edge.sourcePort,
        false,
      );
      final Offset? target = _getPortPosition(
        edge.targetNodeId,
        edge.targetPort,
        true,
      );
      if (source == null || target == null) {
        continue;
      }

      // A wire takes the color of the node it leaves, so a graph reads by
      // signal path the way the Train/Eval wires do (those color by the data
      // kind their port carries — a notion this canvas's PortType, which
      // describes tensor shape, does not have). Wires used to be one uniform
      // outline grey here.
      final Color color = isSelected
          ? primaryColor
          : _edgeColor(edge.sourceNodeId);

      drawCanvasEdge(
        canvas,
        source,
        target,
        color,
        isVertical: isVertical,
        strokeWidth: canvasEdgeStrokeWidth(
          isSelected: isSelected,
          weight: strokeWeight,
        ),
        // Dashed stroke marks a plastic (learning-rule) edge.
        dashed: edge.parameters['hasLearningRule'] == true,
      );

      // ── Learning rule badge ──────────────────────────────────────────────
      final String? learningRule = edge.parameters['learningRuleKind']
          ?.toString();
      if (learningRule != null) {
        // ZETA-MIGRATION-EXEMPT: categorical data-viz color, no Zeta
        // equivalent for N-way distinct hues (one per learning-rule kind).
        final Color badgeColor = switch (learningRule) {
          'stdp' => const Color(0xFFFFC107),
          'surrogate_gradient' => const Color(0xFF2196F3),
          'hebbian' => const Color(0xFF4CAF50),
          _ => const Color(0xFF9E9E9E),
        };
        final String abbr = switch (learningRule) {
          'stdp' => 'S',
          'surrogate_gradient' => 'SG',
          'hebbian' => 'H',
          _ => '?',
        };
        final Offset mid = canvasEdgeMidpoint(source, target);
        // Circle background
        canvas.drawCircle(mid, 10, Paint()..color = badgeColor);
        // Border so the badge stands out on any background
        canvas.drawCircle(
          mid,
          10,
          Paint()
            ..color = badgeAccentColor.withValues(alpha: 0.2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        // Abbreviation text
        // ZETA-MIGRATION-EXEMPT: drawn inside CustomPainter.paint, which has
        // no BuildContext to reach Zeta.of(context); badge also needs an
        // 8px size below Zeta's smallest text preset (12px) to fit the dot.
        final TextPainter tp = TextPainter(
          text: TextSpan(
            text: abbr,
            style: TextStyle(
              color: badgeAccentColor,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
      }
    }

    if (connectingFromNodeId != null &&
        connectingFromPortId != null &&
        currentConnectingPoint != null) {
      final Offset? source = _getPortPosition(
        connectingFromNodeId!,
        connectingFromPortId!,
        false,
      );
      if (source != null) {
        // Stylus pressure only scales the uncommitted preview wire.
        drawCanvasEdge(
          canvas,
          source,
          currentConnectingPoint!,
          primaryColor.withValues(alpha: 0.8),
          isVertical: isVertical,
          strokeWidth: (1.5 + currentConnectingPressure * 3.0).clamp(1.0, 6.0),
          arrowhead: false,
        );
      }
    }
    canvas.restore();
  }

  /// Accent color of the node a wire leaves, falling back to the theme's
  /// outline color when the node or its type no longer resolves.
  Color _edgeColor(String sourceNodeId) {
    for (final CanvasNode node in graph.nodes) {
      if (node.id != sourceNodeId) continue;
      final String? category =
          nirTypeMap[node.nirType ?? node.componentId]?.category ??
          node.metadata['category']?.toString();
      if (category == null) break;
      return canvasCategoryColor(category);
    }
    return outlineColor;
  }

  Offset? _getPortPosition(String nodeId, String portId, bool isInput) {
    final CanvasNode? node = graph.nodes.cast<CanvasNode?>().firstWhere(
      (CanvasNode? n) => n?.id == nodeId,
      orElse: () => null,
    );
    if (node == null) {
      return null;
    }
    final NirNodeType? nodeType = nirTypeMap[node.nirType ?? node.componentId];
    if (nodeType == null) {
      return null;
    }
    final List<NirPortDef> ports = nodeType.ports
        .where((NirPortDef p) => p.direction == (isInput ? 'input' : 'output'))
        .toList();
    final int index = ports.indexWhere((NirPortDef p) => p.id == portId);
    if (index == -1) {
      return null;
    }
    return Offset(node.position[0], node.position[1]) +
        networkPortCentre(
          node: node,
          index: index,
          count: ports.length,
          cardSize: networkNodeSize(node, nodeType, compact: isVertical),
          isInput: isInput,
          compact: isVertical,
        );
  }

  @override
  bool shouldRepaint(covariant ConnectionPainter oldDelegate) {
    return oldDelegate.graph != graph ||
        oldDelegate.currentConnectingPoint != currentConnectingPoint ||
        oldDelegate.currentConnectingPressure != currentConnectingPressure ||
        oldDelegate.selectedEdgeId != selectedEdgeId ||
        oldDelegate.connectingFromNodeId != connectingFromNodeId ||
        oldDelegate.connectingFromPortId != connectingFromPortId ||
        oldDelegate.sceneOrigin != sceneOrigin ||
        oldDelegate.isVertical != isVertical;
  }
}
