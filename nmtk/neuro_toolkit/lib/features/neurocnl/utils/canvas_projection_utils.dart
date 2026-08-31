import 'package:flutter/material.dart' show Color;
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' show ZetaColors;

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart' as canonical;

/// Resolves the display name for a canvas node: an explicit [CanvasNode.label]
/// wins, then the `name` parameter (set by NIR/CNL projection), and only
/// falls back to the raw internal node id if neither is present.
String resolveNodeDisplayName(CanvasNode node) {
  return node.label ?? node.parameters['name']?.toString() ?? node.id;
}

String _normalizeForMatch(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Resolves backend `layer_spike_rates` keys back to the canvas node ids they
/// describe. The backend derives each key from the exported NIR graph's node
/// key, which — for a canvas-authored network — is the canvas node's own
/// `id` (see `nir_graph_serializer.py`'s `nodes[node.id] = ...`), sanitized
/// with the same non-alphanumeric-stripping rule as [_normalizeForMatch].
/// `id`s are unique by construction, so this match is exact and never
/// ambiguous — unlike matching on [resolveNodeDisplayName], which collapses
/// to the generic type name ("LIF") for every instance of that node type.
///
/// Falls back to a display-name match (kept for NIR files imported with
/// real, human-authored population names, where the backend key may not be
/// id-derived) only when no node's `id` matches; a key with zero or more
/// than one matching node on that fallback path is dropped rather than
/// guessed.
Map<String, double> matchSpikeRatesToNodeIds(
  Map<String, double> ratesByBackendKey,
  List<CanvasNode> nodes,
) {
  final byNormalizedId = <String, String>{};
  final byNormalizedName = <String, List<String>>{};
  for (final node in nodes) {
    byNormalizedId[_normalizeForMatch(node.id)] = node.id;
    byNormalizedName
        .putIfAbsent(_normalizeForMatch(resolveNodeDisplayName(node)), () => [])
        .add(node.id);
  }
  final result = <String, double>{};
  ratesByBackendKey.forEach((key, rate) {
    final normalizedKey = _normalizeForMatch(key);
    final idMatch = byNormalizedId[normalizedKey];
    if (idMatch != null) {
      result[idMatch] = rate;
      return;
    }
    final nameMatches = byNormalizedName[normalizedKey];
    if (nameMatches != null && nameMatches.length == 1) {
      result[nameMatches.first] = rate;
    }
  });
  return result;
}

/// Human labels for activity-export bucket keys (the `hidden` in
/// `hidden_spikes.npy`), keyed by the original bucket key.
///
/// For a canvas-authored network the bucket key is the canvas node's own `id`
/// run through the backend's `_python_identifier` slugifier, so it arrives as
/// something like `nir_lif_1785492030598` and is unusable as a UI label. This
/// resolves each key back to its canvas node using the same normalization rule
/// as [matchSpikeRatesToNodeIds] and returns [resolveNodeDisplayName] instead.
///
/// Display names collapse to the bare type name for every instance of a type
/// ("LIF", "LIF"), so same-named results are numbered in the key order given.
/// Keys with no matching node keep a title-cased form of the key itself, which
/// is what NIR files imported with real population names ("hidden") already
/// produce.
String _nodeLayerLabel(CanvasNode node) {
  final name = resolveNodeDisplayName(node);
  // `resolveNodeDisplayName` falls back to the raw internal id, which for a
  // canvas-created node is `nir.LIF_1785492030598` — no better as a label than
  // the slug we're trying to replace. Use the node's type instead, which the
  // duplicate-numbering below turns into "LIF 1"/"LIF 2".
  if (name != node.id) return name;
  final type = node.nirType ?? node.componentId;
  final shortType = type.contains('.') ? type.split('.').last : type;
  return shortType.isEmpty ? node.id : shortType;
}

Map<String, String> resolveActivityLayerLabels(
  Iterable<String> bucketKeys,
  List<CanvasNode> nodes,
) {
  final nodeByNormalizedId = <String, CanvasNode>{};
  for (final node in nodes) {
    nodeByNormalizedId[_normalizeForMatch(node.id)] = node;
  }

  final rawLabels = <String, String>{};
  final labelCounts = <String, int>{};
  for (final key in bucketKeys) {
    final node = nodeByNormalizedId[_normalizeForMatch(key)];
    final label = node != null
        ? _nodeLayerLabel(node)
        : (key.isEmpty ? key : key[0].toUpperCase() + key.substring(1));
    rawLabels[key] = label;
    labelCounts[label] = (labelCounts[label] ?? 0) + 1;
  }

  final seen = <String, int>{};
  final result = <String, String>{};
  rawLabels.forEach((key, label) {
    if ((labelCounts[label] ?? 0) <= 1) {
      result[key] = label;
      return;
    }
    final n = (seen[label] ?? 0) + 1;
    seen[label] = n;
    result[key] = '$label $n';
  });
  return result;
}

/// Prettifies a single raw layer identifier such as `nir.LIF_1785492030598`
/// (the Akida deploy panel's `layer.name` form) or `nir_lif_1785492030598`
/// (the activity-export bucket key form used by [_nodeLayerLabel]) into a
/// short type label ("LIF"). Unlike [resolveActivityLayerLabels], this has no
/// canvas node to match against — it works on the raw string alone, which is
/// what the Akida deploy/benchmark result carries. Falls back to a
/// title-cased form of the raw string when it doesn't match the
/// `<type>[_.]<digits>` id-slug shape, which is what a real, human-authored
/// NIR population name (e.g. "hidden") already looks like.
String prettifyLayerIdentifier(String rawName) {
  final match = RegExp(r'([A-Za-z]+)[_.]?\d+$').firstMatch(rawName);
  final candidate = match?.group(1);
  if (candidate != null && candidate.isNotEmpty) return candidate;
  return rawName.isEmpty
      ? rawName
      : rawName[0].toUpperCase() + rawName.substring(1);
}

/// Runs [prettifyLayerIdentifier] over [rawNames] and numbers duplicates in
/// iteration order ("LIF 1", "LIF 2"), the same scheme
/// [resolveActivityLayerLabels] uses, so an Akida panel and the Raster tab
/// read the same way for repeated layer types.
List<String> numberLayerLabels(Iterable<String> rawNames) {
  final rawLabels = [
    for (final name in rawNames) prettifyLayerIdentifier(name),
  ];
  final labelCounts = <String, int>{};
  for (final label in rawLabels) {
    labelCounts[label] = (labelCounts[label] ?? 0) + 1;
  }
  final seen = <String, int>{};
  final result = <String>[];
  for (final label in rawLabels) {
    if ((labelCounts[label] ?? 0) <= 1) {
      result.add(label);
      continue;
    }
    final n = (seen[label] ?? 0) + 1;
    seen[label] = n;
    result.add('$label $n');
  }
  return result;
}

/// Shared spike-rate → color tiering, used by both the Results step's spike-
/// rate legend and the canvas node highlight so "hot" always means the same
/// thing in both places.
Color spikeRateColor(double rate, ZetaColors colors) {
  if (rate < 0.1) return colors.mainInfo;
  if (rate < 0.4) return colors.mainWarning;
  return colors.mainNegative;
}

/// Maps each known NIR primitive type to the [CanvasNode.componentId] value
/// (i.e. [NirNodeType.legacyComponentId]) used by the canvas registry.
///
/// When [canonical.CanvasNode.nirType] is absent (pre-fix backend) the caller
/// falls back to `'nir.LIF'`, which maps to `'lif_population'` — identical to
/// the previous hardcoded behaviour.
const Map<String, String> _nirTypeToComponentId = {
  'nir.Input': 'input_node',
  'nir.Output': 'output_node',
  'nir.LIF': 'lif_population',
  'nir.CubaLIF': 'lif_population',
  'nir.IF': 'lif_population',
  'nir.LI': 'lif_population',
  'nir.Linear': 'nir.Linear',
  'nir.Affine': 'nir.Affine',
  'nir.Conv1d': 'nir.Conv1d',
  'nir.Conv2d': 'nir.Conv2d',
  'nir.Flatten': 'nir.Flatten',
  'nir.AvgPool2d': 'nir.AvgPool2d',
  'nir.SumPool2d': 'nir.SumPool2d',
  'nir.Delay': 'nir.Delay',
  'nir.Scale': 'nir.Scale',
};

/// Project a [canonical.CanvasProjection] into a [CanvasGraph], preserving
/// node positions from [currentGraph] for nodes that already exist.
CanvasGraph canvasGraphFromCanonical(
  canonical.CanvasProjection projection, {
  required CanvasGraph currentGraph,
}) {
  final existingNodes = <String, CanvasNode>{
    for (final node in currentGraph.nodes) node.id: node,
  };

  final nodes = <CanvasNode>[
    for (var index = 0; index < projection.nodes.length; index++)
      () {
        final rawNirType = projection.nodes[index].nirType;
        final resolvedNirType = rawNirType ?? 'nir.LIF';
        final resolvedComponentId =
            _nirTypeToComponentId[resolvedNirType] ?? resolvedNirType;

        final existingNode = existingNodes[projection.nodes[index].id];

        return CanvasNode(
          id: projection.nodes[index].id,
          componentId: resolvedComponentId,
          nirType: resolvedNirType,
          label: projection.nodes[index].label,
          parameters: <String, dynamic>{
            if (existingNode != null) ...existingNode.parameters,
            ...projection.nodes[index].parameters,
            'name': projection.nodes[index].label,
            'n_neurons':
                projection.nodes[index].parameters['n_neurons'] ??
                projection.nodes[index].size,
            if (projection.nodes[index].shape != null)
              'shape': projection.nodes[index].shape,
            if (projection.nodes[index].threshold != null)
              'threshold': projection.nodes[index].threshold,
            if (projection.nodes[index].tau != null)
              'tau_rc': projection.nodes[index].tau,
          },
          position:
              existingNode?.position ?? <double>[80.0 + (index * 220.0), 160.0],
          metadata: <String, dynamic>{
            if (existingNode != null) ...existingNode.metadata,
            ...projection.nodes[index].metadata,
            if (existingNode == null &&
                projection.nodes[index].metadata.isEmpty)
              'category': 'neuron',
          },
        );
      }(),
  ];

  final edges = <CanvasEdge>[
    for (var index = 0; index < projection.edges.length; index++)
      () {
        final source = projection.edges[index].source;
        final target = projection.edges[index].target;
        // Try to match existing edge by source and target
        final existingEdge = currentGraph.edges
            .where((e) => e.sourceNodeId == source && e.targetNodeId == target)
            .firstOrNull;

        return CanvasEdge(
          id: existingEdge?.id ?? 'edge_$index',
          sourceNodeId: source,
          sourcePort: 'out',
          targetNodeId: target,
          targetPort: 'in',
          parameters: <String, dynamic>{
            if (existingEdge != null) ...existingEdge.parameters,
            'synapse_type': 'static_synapse',
            if (projection.edges[index].weight != null)
              'weight': projection.edges[index].weight,
            if (projection.edges[index].polarity != 'excitatory')
              'polarity': projection.edges[index].polarity,
            if (projection.edges[index].connectivityPattern != null)
              'connectivity_pattern':
                  projection.edges[index].connectivityPattern,
            if (projection.edges[index].hasLearningRule)
              'hasLearningRule': true,
            if (projection.edges[index].learningRuleKind != null)
              'learningRuleKind': projection.edges[index].learningRuleKind,
          },
        );
      }(),
  ];

  // Collect advisory FidelityAnnotations for edges that carry a learning rule.
  // These are stored in the graph metadata so the existing annotation display
  // can surface them without requiring a separate model field.
  final List<Map<String, dynamic>> learningRuleAnnotations = [
    for (final edge in projection.edges)
      if (edge.learningRuleKind != null)
        canonical.FidelityAnnotation(
          kind: 'advisory',
          concept: 'learning_rule',
          message:
              'Edge ${edge.source}→${edge.target} uses learning rule '
              '"${edge.learningRuleKind}". Ensure the target backend '
              'supports this plasticity mechanism.',
          affects: [edge.source, edge.target],
        ).toJson(),
  ];

  final Map<String, dynamic> updatedMetadata = <String, dynamic>{
    ...currentGraph.metadata,
    ...projection.metadata,
    if (learningRuleAnnotations.isNotEmpty)
      'learning_rule_annotations': learningRuleAnnotations,
  };
  // A spread-merge only adds/overwrites keys — it never deletes one, so a
  // network timestep declared on a previously-open graph would otherwise
  // leak forward into a freshly-loaded graph that declares none.
  if (!projection.metadata.containsKey('dt')) {
    updatedMetadata.remove('dt');
  }

  return currentGraph.copyWith(
    nodes: nodes,
    edges: edges,
    metadata: updatedMetadata,
  );
}
