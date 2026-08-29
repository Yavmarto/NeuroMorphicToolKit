import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/component.dart';

const canonicalCanvasNodeRoles = <String>['sensory', 'motor'];
const canonicalCanvasNodeComponentId = 'lif_population';
const canonicalCanvasSynapseId = 'static_synapse';

String normalizedCanvasNodeName(CanvasNode node) {
  final rawName = node.parameters['name'];
  return rawName is String ? rawName.trim().toLowerCase() : '';
}

List<String> availableCanonicalCanvasRoles(
  CanvasGraph graph, {
  String? excludingNodeId,
}) {
  final takenRoles = <String>{};
  for (final node in graph.nodes) {
    if (node.id == excludingNodeId) {
      continue;
    }
    final normalizedName = normalizedCanvasNodeName(node);
    if (normalizedName.isNotEmpty) {
      takenRoles.add(normalizedName);
    }
  }

  return canonicalCanvasNodeRoles
      .where((role) => !takenRoles.contains(role))
      .toList(growable: false);
}

String? nextCanonicalCanvasRole(CanvasGraph graph) {
  final availableRoles = availableCanonicalCanvasRoles(graph);
  return availableRoles.isEmpty ? null : availableRoles.first;
}

bool isSupportedCanonicalCanvasComponent(ComponentBlock component) {
  if (component.isSynapse) {
    return component.id == canonicalCanvasSynapseId;
  }
  return component.id == canonicalCanvasNodeComponentId;
}

String? unsupportedCanonicalCanvasComponentReason(
  CanvasGraph graph,
  ComponentBlock component,
) {
  if (component.isSynapse) {
    if (component.id != canonicalCanvasSynapseId) {
      return 'Only static synapses are supported by canonical NeuroCNL canvas sync.';
    }
    return null;
  }

  if (component.id != canonicalCanvasNodeComponentId) {
    return 'Only LIF populations are supported by canonical NeuroCNL canvas sync.';
  }

  if (nextCanonicalCanvasRole(graph) == null) {
    return 'The canonical canvas supports exactly two populations: sensory and motor.';
  }

  return null;
}

String? unsupportedCanonicalConnectionReason(
  CanvasGraph graph, {
  required String sourceNodeId,
  required String targetNodeId,
}) {
  if (graph.edges.isNotEmpty) {
    return 'The canonical canvas supports exactly one sensory -> motor connection.';
  }

  CanvasNode? sourceNode;
  CanvasNode? targetNode;
  for (final node in graph.nodes) {
    if (node.id == sourceNodeId) {
      sourceNode = node;
    } else if (node.id == targetNodeId) {
      targetNode = node;
    }
  }
  if (sourceNode == null || targetNode == null) {
    return 'Connections require both sensory and motor populations.';
  }

  final sourceRole = normalizedCanvasNodeName(sourceNode);
  final targetRole = normalizedCanvasNodeName(targetNode);
  if (sourceRole != 'sensory' || targetRole != 'motor') {
    return 'Canonical NeuroCNL only supports a sensory -> motor connection.';
  }

  return null;
}
