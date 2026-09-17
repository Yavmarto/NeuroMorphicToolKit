import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';

part 'cnl_line_node_map_provider.g.dart';

/// Derived mapping between CNL line numbers and canvas node IDs.
///
/// Built by joining [pipelineProvider]'s parsed sentences against
/// [canvasProvider]'s nodes using a case-insensitive label/name match.
/// Recomputed automatically by Riverpod whenever either source changes.
///
/// **Match priority** (first hit wins per node):
///   1. `CanvasNode.label`
///   2. `CanvasNode.parameters['name']`
///   3. `CanvasNode.id`
///
/// Cost: O(sentences + nodes) per update — negligible for typical CNL
/// documents (<200 lines).
@riverpod
({Map<int, String> lineToNode, Map<String, int> nodeToLine}) cnlLineNodeMap(
  Ref ref,
) {
  final List<ParseSentence> sentences = ref.watch(
    pipelineProvider.select((p) => p.parseResult?.sentences ?? const []),
  );
  final List<CanvasNode> nodes = ref.watch(
    canvasProvider.select((c) => c.graph.nodes),
  );

  return buildCnlLineNodeMap(sentences, nodes);
}

/// Builds the CNL/canvas lookup maps without Riverpod dependencies.
///
/// Keeping the matching logic pure makes the name-resolution contract easy to
/// test and guarantees invalid or stale parse output cannot affect UI focus.
({Map<int, String> lineToNode, Map<String, int> nodeToLine})
buildCnlLineNodeMap(List<ParseSentence> sentences, List<CanvasNode> nodes) {
  // Build a name→nodeId lookup from canvas nodes (case-insensitive).
  final Map<String, String> nameToId = <String, String>{
    for (final CanvasNode n in nodes)
      (n.label ?? n.parameters['name']?.toString() ?? n.id)
              .toLowerCase()
              .trim():
          n.id,
  };

  final Map<int, String> lineToNode = <int, String>{};
  final Map<String, int> nodeToLine = <String, int>{};

  for (final ParseSentence s in sentences) {
    if (!s.valid || s.parsed == null) continue;
    final String subject = s.parsed!.subject.toLowerCase().trim();
    final String? nodeId = nameToId[subject];
    if (nodeId == null) continue;
    lineToNode[s.line] = nodeId;
    // Only the first matching line wins in nodeToLine.
    nodeToLine.putIfAbsent(nodeId, () => s.line);
  }

  return (lineToNode: lineToNode, nodeToLine: nodeToLine);
}
