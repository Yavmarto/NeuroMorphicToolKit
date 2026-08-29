import 'package:json_annotation/json_annotation.dart';
part 'canvas.g.dart';

class CanvasViewport {
  const CanvasViewport({this.zoom = 1.0, this.pan = const [0.0, 0.0]});

  final double zoom;
  final List<double> pan;

  static const CanvasViewport defaults = CanvasViewport(pan: [0.0, 120.0]);

  /// Reads a stored camera out of a graph's metadata. `graph.metadata` is the
  /// *serialization* format for the viewport at project boundaries only — the
  /// live value is `CanvasState.viewport`. Missing/malformed keys fall back to
  /// [defaults] so an older project without a stored camera still loads.
  factory CanvasViewport.fromMetadata(Map<String, dynamic> metadata) {
    final zoom = (metadata['zoom'] as num?)?.toDouble() ?? defaults.zoom;
    final panRaw = metadata['pan'];
    final pan = panRaw is List && panRaw.length >= 2
        ? [
            (panRaw[0] as num?)?.toDouble() ?? defaults.pan[0],
            (panRaw[1] as num?)?.toDouble() ?? defaults.pan[1],
          ]
        : defaults.pan;
    return CanvasViewport(zoom: zoom, pan: pan);
  }

  /// Inverse of [CanvasViewport.fromMetadata] — folds the live camera back into
  /// a graph's metadata so saving a project stores it.
  Map<String, dynamic> applyToMetadata(Map<String, dynamic> metadata) {
    return <String, dynamic>{
      ...metadata,
      'zoom': zoom,
      'pan': [pan[0], pan[1]],
    };
  }

  bool isCloseTo(CanvasViewport other, {double tolerance = 0.001}) {
    return (zoom - other.zoom).abs() <= tolerance &&
        (pan[0] - other.pan[0]).abs() <= tolerance &&
        (pan[1] - other.pan[1]).abs() <= tolerance;
  }

  // Value equality so `ref.watch/listen(canvasProvider.select((s) => s.viewport))`
  // actually dedupes — without it the default identity comparison would fire on
  // every pan frame, which is the whole thing CanvasState.viewport exists to avoid.
  @override
  bool operator ==(Object other) =>
      other is CanvasViewport &&
      other.zoom == zoom &&
      other.pan[0] == pan[0] &&
      other.pan[1] == pan[1];

  @override
  int get hashCode => Object.hash(zoom, pan[0], pan[1]);
}

@JsonSerializable()
class CanvasNode {
  final String id;
  @JsonKey(name: 'component_id')
  final String componentId;
  @JsonKey(name: 'nir_type')
  final String? nirType;
  final String? label;
  final Map<String, dynamic> parameters;
  final List<double> position;
  final double width;
  final double height;
  @JsonKey(name: 'is_visible')
  final bool isVisible;
  final Map<String, dynamic> metadata;
  CanvasNode({
    required this.id,
    required this.componentId,
    this.nirType,
    this.label,
    required this.parameters,
    required this.position,
    this.width = 150.0,
    this.height = 132.0,
    this.isVisible = true,
    this.metadata = const <String, dynamic>{},
  });
  factory CanvasNode.fromJson(Map<String, dynamic> json) =>
      _$CanvasNodeFromJson(json);
  Map<String, dynamic> toJson() => _$CanvasNodeToJson(this);
  CanvasNode copyWith({
    String? id,
    String? componentId,
    String? nirType,
    bool clearNirType = false,
    String? label,
    bool clearLabel = false,
    Map<String, dynamic>? parameters,
    List<double>? position,
    double? width,
    double? height,
    bool? isVisible,
    Map<String, dynamic>? metadata,
  }) {
    return CanvasNode(
      id: id ?? this.id,
      componentId: componentId ?? this.componentId,
      nirType: clearNirType ? null : (nirType ?? this.nirType),
      label: clearLabel ? null : (label ?? this.label),
      parameters: parameters ?? this.parameters,
      position: position ?? this.position,
      width: width ?? this.width,
      height: height ?? this.height,
      isVisible: isVisible ?? this.isVisible,
      metadata: metadata ?? this.metadata,
    );
  }
}

@JsonSerializable()
class CanvasEdge {
  final String id;
  @JsonKey(name: 'source_node_id')
  final String sourceNodeId;
  @JsonKey(name: 'source_port')
  final String sourcePort;
  @JsonKey(name: 'target_node_id')
  final String targetNodeId;
  @JsonKey(name: 'target_port')
  final String targetPort;
  final Map<String, dynamic> parameters;
  CanvasEdge({
    required this.id,
    required this.sourceNodeId,
    required this.sourcePort,
    required this.targetNodeId,
    required this.targetPort,
    required this.parameters,
  });
  factory CanvasEdge.fromJson(Map<String, dynamic> json) =>
      _$CanvasEdgeFromJson(json);
  Map<String, dynamic> toJson() => _$CanvasEdgeToJson(this);
  CanvasEdge copyWith({
    String? id,
    String? sourceNodeId,
    String? sourcePort,
    String? targetNodeId,
    String? targetPort,
    Map<String, dynamic>? parameters,
  }) {
    return CanvasEdge(
      id: id ?? this.id,
      sourceNodeId: sourceNodeId ?? this.sourceNodeId,
      sourcePort: sourcePort ?? this.sourcePort,
      targetNodeId: targetNodeId ?? this.targetNodeId,
      targetPort: targetPort ?? this.targetPort,
      parameters: parameters ?? this.parameters,
    );
  }
}

@JsonSerializable()
class CanvasGraph {
  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;
  final Map<String, dynamic> metadata;
  CanvasGraph({
    required this.nodes,
    required this.edges,
    required this.metadata,
  });
  factory CanvasGraph.fromJson(Map<String, dynamic> json) =>
      _$CanvasGraphFromJson(json);
  Map<String, dynamic> toJson() => _$CanvasGraphToJson(this);

  CanvasGraph copyWith({
    List<CanvasNode>? nodes,
    List<CanvasEdge>? edges,
    Map<String, dynamic>? metadata,
  }) {
    return CanvasGraph(
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
      metadata: metadata ?? this.metadata,
    );
  }
}
