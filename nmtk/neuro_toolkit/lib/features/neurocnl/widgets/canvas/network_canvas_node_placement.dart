import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/nir_types_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/nir_node_type_resolver.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/nir_node_type_suggestions.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_shared_widgets.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_stylus_layer.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_viewport.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_canvas_connections.dart';

/// Node creation, placement and hit-testing for [NetworkCanvas]: resolving
/// what's under a scene point, erasing with the stylus eraser tip, and
/// turning a palette drag / handwritten label into a new node.
///
/// Implements the [CanvasStylusMixin] hooks (empty-canvas hit-testing, lasso
/// selection, handwriting-to-node) that are specific to this canvas's node
/// model; the lasso/handwriting mechanics themselves live in
/// [CanvasStylusMixin], shared with the Train/Eval canvases.
mixin NetworkCanvasNodePlacementMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T>
    implements
        CanvasViewportMixin<T>,
        CanvasStylusMixin<T>,
        NetworkCanvasConnectionMixin<T> {
  CanvasNode? networkNodeAtPosition(Offset pos, CanvasGraph graph) {
    final Map<String, NirNodeType> nirTypeMap = ref.read(
      nirNodeTypeMapProvider,
    );
    for (final CanvasNode node in graph.nodes.reversed) {
      final Size cardSize = networkNodeSize(
        node,
        resolveNetworkNodeType(nirTypeMap, node),
        compact: networkIsVertical,
      );
      final Rect bounds = Rect.fromLTWH(
        node.position[0],
        node.position[1],
        cardSize.width,
        cardSize.height,
      );
      if (bounds.contains(pos)) {
        return node;
      }
    }
    return null;
  }

  void networkEraseAt(Offset globalPosition) {
    final RenderBox box = context.findRenderObject()! as RenderBox;
    final Offset scenePos = canvasSceneFromViewport(
      box.globalToLocal(globalPosition),
    );
    final CanvasGraph graph = ref.read(canvasProvider).graph;
    final CanvasNode? node = networkNodeAtPosition(scenePos, graph);
    if (node != null) {
      ref.read(canvasProvider.notifier).removeNode(node.id);
      return;
    }
    final CanvasEdge? edge = networkFindEdgeAtPosition(
      scenePos,
      graph,
      ref.read(nirNodeTypeMapProvider),
    );
    if (edge != null) {
      ref.read(canvasProvider.notifier).removeEdge(edge.id);
    }
  }

  void networkCreateNodeAt(NirNodeType type, Offset scenePos) {
    final String id = '${type.id}_${DateTime.now().millisecondsSinceEpoch}';
    final int nextIndex = ref.read(canvasProvider).graph.nodes.length + 1;

    ref
        .read(canvasProvider.notifier)
        .addNode(
          CanvasNode(
            id: id,
            componentId: type.legacyComponentId ?? type.id,
            nirType: type.isCustom ? type.baseNirType : type.id,
            label: type.displayName,
            parameters: <String, dynamic>{
              ...type.defaultParameters,
              'name': '${type.displayName} $nextIndex',
            },
            position: <double>[scenePos.dx, scenePos.dy],
            width: kCanvasNodeWidth,
            height: kCanvasNodeBaseHeight,
            metadata: <String, dynamic>{'category': type.category},
          ),
          preferRight: !networkIsVertical,
        );
  }

  void networkHandleNodeDrop(DragTargetDetails<NirNodeType> details) {
    final RenderBox box = context.findRenderObject()! as RenderBox;
    final Offset localPos = box.globalToLocal(details.offset);
    final Offset scenePos = canvasSceneFromViewport(localPos);
    networkCreateNodeAt(details.data, scenePos);
  }

  // ── Stylus-on-empty-canvas: lasso selection & handwriting-to-node ───────
  //
  // The behaviour itself lives in CanvasStylusMixin (shared with the Train
  // and Eval canvases). These four hooks are the Architecture-specific
  // parts: what counts as empty canvas here, what "select in this rect"
  // means, and how handwritten text becomes a NIR node.

  @override
  bool canvasIsEmptyAt(Offset scenePosition) {
    final CanvasGraph graph = ref.read(canvasProvider).graph;
    if (networkNodeAtPosition(scenePosition, graph) != null) {
      return false;
    }
    final Map<String, NirNodeType> nirTypeMap = ref.read(
      nirNodeTypeMapProvider,
    );
    for (final CanvasNode node in graph.nodes) {
      final NirNodeType? nodeType = resolveNetworkNodeType(nirTypeMap, node);
      if (nodeType == null) {
        continue;
      }
      for (final NirPortDef port in nodeType.ports) {
        final Offset? portPos = networkGetPortPosition(
          graph,
          nirTypeMap,
          node.id,
          port.id,
          port.direction == 'input',
        );
        if (portPos != null &&
            (portPos - scenePosition).distance <=
                kCanvasPortHitTargetSize / 2) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  void canvasSelectInRect(Rect sceneRect) =>
      ref.read(canvasProvider.notifier).selectNodesInRect(sceneRect);

  @override
  List<String> canvasSuggestNodeTypes(String query) => suggestNirNodeTypes(
    query,
    ref.read(nirNodeTypeMapProvider),
  ).map((NirNodeType type) => type.displayName).toList();

  @override
  void canvasCreateNodeFromText(String text, Offset scenePosition) {
    final NirNodeType? type = resolveNirNodeType(
      text,
      ref.read(nirNodeTypeMapProvider),
    );
    if (type == null) {
      if (text.trim().isNotEmpty) {
        NmtkSnackBars.info(context, "No matching node type for '$text'.");
      }
      return;
    }
    networkCreateNodeAt(type, scenePosition);
  }
}
