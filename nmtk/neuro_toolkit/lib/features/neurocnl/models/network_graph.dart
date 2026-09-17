/// Position of a node in the network graph.
class NodePosition {
  final double x;
  final double y;

  const NodePosition({required this.x, required this.y});

  factory NodePosition.fromJson(Map<String, dynamic> json) {
    return NodePosition(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{'x': x, 'y': y};
}

/// A node in the generated network graph.
class NetworkNode {
  final String id;
  final String type;
  final String subtype;
  final String label;
  final Map<String, Object?> params;
  final NodePosition? position;

  const NetworkNode({
    required this.id,
    required this.type,
    required this.subtype,
    required this.label,
    required this.params,
    this.position,
  });

  factory NetworkNode.fromJson(Map<String, dynamic> json) {
    return NetworkNode(
      id: json['id'] as String,
      type: json['type'] as String,
      subtype: json['subtype'] as String? ?? 'generic',
      label: json['label'] as String,
      params: Map<String, Object?>.from(json['params'] as Map? ?? {}),
      position: json['position'] != null
          ? NodePosition.fromJson(json['position'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'type': type,
    'subtype': subtype,
    'label': label,
    'params': params,
    'position': position?.toJson(),
  };
}

/// An edge (connection) in the generated network graph.
class NetworkEdge {
  final String id;
  final String source;
  final String target;
  final bool isInhibitory;
  final bool hasLearningRule;
  final String? learningRule;
  final double? learningRate;
  final bool hasDelay;
  final Map<String, Object?> params;

  const NetworkEdge({
    required this.id,
    required this.source,
    required this.target,
    required this.isInhibitory,
    required this.hasLearningRule,
    this.learningRule,
    this.learningRate,
    required this.hasDelay,
    required this.params,
  });

  factory NetworkEdge.fromJson(Map<String, dynamic> json) {
    return NetworkEdge(
      id: json['id'] as String,
      source: json['source'] as String,
      target: json['target'] as String,
      isInhibitory: json['is_inhibitory'] as bool? ?? false,
      hasLearningRule: json['has_learning_rule'] as bool? ?? false,
      learningRule: json['learning_rule'] as String?,
      learningRate: (json['learning_rate'] as num?)?.toDouble(),
      hasDelay: json['has_delay'] as bool? ?? false,
      params: Map<String, Object?>.from(json['params'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'source': source,
    'target': target,
    'is_inhibitory': isInhibitory,
    'has_learning_rule': hasLearningRule,
    'learning_rule': learningRule,
    'learning_rate': learningRate,
    'has_delay': hasDelay,
    'params': params,
  };
}

/// The full network graph returned by /api/generate.
class NetworkGraph {
  final List<NetworkNode> nodes;
  final List<NetworkEdge> edges;

  const NetworkGraph({required this.nodes, required this.edges});

  factory NetworkGraph.fromJson(Map<String, dynamic> json) {
    return NetworkGraph(
      nodes: (json['nodes'] as List)
          .map((n) => NetworkNode.fromJson(n as Map<String, dynamic>))
          .toList(),
      edges: (json['edges'] as List)
          .map((e) => NetworkEdge.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'nodes': nodes.map((node) => node.toJson()).toList(growable: false),
    'edges': edges.map((edge) => edge.toJson()).toList(growable: false),
  };
}

/// Generate response: network + round-tripable CNL + NIR preview.
class GenerateResult {
  final NetworkGraph network;
  final String cnlDocument;
  final String nirCode;

  const GenerateResult({
    required this.network,
    required this.cnlDocument,
    required this.nirCode,
  });

  factory GenerateResult.fromJson(Map<String, dynamic> json) {
    return GenerateResult(
      network: NetworkGraph.fromJson(json['network'] as Map<String, dynamic>),
      cnlDocument: json['cnl_document'] as String,
      nirCode: json['nir_code'] as String,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'network': network.toJson(),
    'cnl_document': cnlDocument,
    'nir_code': nirCode,
  };
}
