import 'dart:convert';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';

const String kCanvasClipboardMime = 'application/vnd.neurocnl.canvas+json';

class CanvasClipboardPayload {
  const CanvasClipboardPayload({
    required this.nodes,
    required this.edges,
    this.version = 1,
  });

  final int version;
  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version,
    'nodes': nodes.map((CanvasNode n) => n.toJson()).toList(),
    'edges': edges.map((CanvasEdge e) => e.toJson()).toList(),
  };

  factory CanvasClipboardPayload.fromJson(Map<String, dynamic> json) {
    final rawNodes = json['nodes'];
    final rawEdges = json['edges'];
    return CanvasClipboardPayload(
      version: (json['version'] as num?)?.toInt() ?? 1,
      nodes: rawNodes is List
          ? rawNodes
                .whereType<Map<dynamic, dynamic>>()
                .map(
                  (Map<dynamic, dynamic> item) =>
                      CanvasNode.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
          : const <CanvasNode>[],
      edges: rawEdges is List
          ? rawEdges
                .whereType<Map<dynamic, dynamic>>()
                .map(
                  (Map<dynamic, dynamic> item) =>
                      CanvasEdge.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
          : const <CanvasEdge>[],
    );
  }

  String encode() => jsonEncode(toJson());

  static CanvasClipboardPayload? tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return CanvasClipboardPayload.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  static CanvasClipboardPayload fromSelection({
    required CanvasGraph graph,
    required Set<String> selectedNodeIds,
  }) {
    if (selectedNodeIds.isEmpty) {
      return const CanvasClipboardPayload(
        nodes: <CanvasNode>[],
        edges: <CanvasEdge>[],
      );
    }
    final nodes = graph.nodes
        .where((CanvasNode node) => selectedNodeIds.contains(node.id))
        .toList(growable: false);
    final edges = graph.edges
        .where(
          (CanvasEdge edge) =>
              selectedNodeIds.contains(edge.sourceNodeId) &&
              selectedNodeIds.contains(edge.targetNodeId),
        )
        .toList(growable: false);
    return CanvasClipboardPayload(nodes: nodes, edges: edges);
  }
}
