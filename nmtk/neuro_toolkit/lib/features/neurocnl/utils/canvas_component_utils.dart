import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/component.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canonical_canvas_support.dart';

ComponentBlock? findComponentById(
  Iterable<ComponentBlock> components,
  String componentId,
) {
  for (final component in components) {
    if (component.id == componentId) {
      return component;
    }
  }

  return null;
}

String buildNodeDisplayName(CanvasNode node, {ComponentBlock? component}) {
  final rawName = node.parameters['name'];
  if (rawName is String && rawName.trim().isNotEmpty) {
    return rawName.trim();
  }

  return component?.name ?? _humanizeIdentifier(node.componentId);
}

Map<String, dynamic> buildDefaultNodeParameters(
  CanvasGraph graph,
  ComponentBlock component,
) {
  final nextIndex =
      graph.nodes.where((node) => node.componentId == component.id).length + 1;

  return {
    ...component.defaultParameterValues,
    'name': nextCanonicalCanvasRole(graph) ?? '${component.name} $nextIndex',
  };
}

String buildFallbackComponentName(String componentId) {
  return _humanizeIdentifier(componentId);
}

String _humanizeIdentifier(String value) {
  final words = value.split('_').where((word) => word.trim().isNotEmpty).map((
    word,
  ) {
    final trimmedWord = word.trim();
    if (trimmedWord.isEmpty) {
      return trimmedWord;
    }

    return '${trimmedWord[0].toUpperCase()}${trimmedWord.substring(1)}';
  });

  final label = words.join(' ').trim();
  return label.isEmpty ? value : label;
}
