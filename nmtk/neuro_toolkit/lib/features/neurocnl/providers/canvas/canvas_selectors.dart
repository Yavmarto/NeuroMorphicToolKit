import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';

/// Canvas graph topology — node ids and edges (not per-node parameters).
final canvasGraphTopologyProvider = Provider<CanvasGraph>((ref) {
  return ref.watch(canvasProvider.select((s) => s.graph));
});

final canvasSelectedNodeIdsProvider = Provider<Set<String>>((ref) {
  return ref.watch(canvasProvider.select((s) => s.selectedNodeIds));
});

final canvasSelectedNodeIdProvider = Provider<String?>((ref) {
  return ref.watch(canvasProvider.select((s) => s.primarySelectedNodeId));
});

final canvasSelectedEdgeIdProvider = Provider<String?>((ref) {
  return ref.watch(canvasProvider.select((s) => s.selectedEdgeId));
});

/// Id of the node currently "armed" for deletion by a long-press, or null.
///
/// Ephemeral UI interaction state, not graph data — deliberately kept out of
/// [canvasProvider] (and so out of undo/redo history). A long-press on a
/// node's card sets this; tapping the resulting trash badge removes the node
/// and clears it; tapping anywhere else on the canvas also clears it without
/// deleting. Shared by both the Architecture canvas and the pipeline-phase
/// (Train/Eval/Infer) canvases so long-press-to-delete behaves identically.
class ArmedForDeleteNodeIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? nodeId) => state = nodeId;
}

final armedForDeleteNodeIdProvider =
    NotifierProvider<ArmedForDeleteNodeIdNotifier, String?>(
      ArmedForDeleteNodeIdNotifier.new,
    );

/// Node ids in graph order — rebuild list shells only when topology changes.
final canvasNodeIdsProvider = Provider<List<String>>((ref) {
  final graph = ref.watch(canvasProvider.select((s) => s.graph));
  return graph.nodes.map((CanvasNode n) => n.id).toList(growable: false);
});

final canvasNodeProvider = Provider.family<CanvasNode?, String>((
  ref,
  String nodeId,
) {
  final nodes = ref.watch(
    canvasProvider.select((CanvasState s) => s.graph.nodes),
  );
  for (final CanvasNode node in nodes) {
    if (node.id == nodeId) {
      return node;
    }
  }
  return null;
});

final canvasEdgeProvider = Provider.family<CanvasEdge?, String>((
  ref,
  String edgeId,
) {
  final edges = ref.watch(
    canvasProvider.select((CanvasState s) => s.graph.edges),
  );
  for (final CanvasEdge edge in edges) {
    if (edge.id == edgeId) {
      return edge;
    }
  }
  return null;
});
