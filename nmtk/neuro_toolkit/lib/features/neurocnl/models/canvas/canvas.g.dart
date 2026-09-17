// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'canvas.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CanvasNode _$CanvasNodeFromJson(Map<String, dynamic> json) => CanvasNode(
  id: json['id'] as String,
  componentId: json['component_id'] as String,
  nirType: json['nir_type'] as String?,
  label: json['label'] as String?,
  parameters: json['parameters'] as Map<String, dynamic>,
  position: (json['position'] as List<dynamic>)
      .map((e) => (e as num).toDouble())
      .toList(),
  width: (json['width'] as num?)?.toDouble() ?? 150.0,
  height: (json['height'] as num?)?.toDouble() ?? 132.0,
  isVisible: json['is_visible'] as bool? ?? true,
  metadata:
      json['metadata'] as Map<String, dynamic>? ?? const <String, dynamic>{},
);

Map<String, dynamic> _$CanvasNodeToJson(CanvasNode instance) =>
    <String, dynamic>{
      'id': instance.id,
      'component_id': instance.componentId,
      'nir_type': instance.nirType,
      'label': instance.label,
      'parameters': instance.parameters,
      'position': instance.position,
      'width': instance.width,
      'height': instance.height,
      'is_visible': instance.isVisible,
      'metadata': instance.metadata,
    };

CanvasEdge _$CanvasEdgeFromJson(Map<String, dynamic> json) => CanvasEdge(
  id: json['id'] as String,
  sourceNodeId: json['source_node_id'] as String,
  sourcePort: json['source_port'] as String,
  targetNodeId: json['target_node_id'] as String,
  targetPort: json['target_port'] as String,
  parameters: json['parameters'] as Map<String, dynamic>,
);

Map<String, dynamic> _$CanvasEdgeToJson(CanvasEdge instance) =>
    <String, dynamic>{
      'id': instance.id,
      'source_node_id': instance.sourceNodeId,
      'source_port': instance.sourcePort,
      'target_node_id': instance.targetNodeId,
      'target_port': instance.targetPort,
      'parameters': instance.parameters,
    };

CanvasGraph _$CanvasGraphFromJson(Map<String, dynamic> json) => CanvasGraph(
  nodes: (json['nodes'] as List<dynamic>)
      .map((e) => CanvasNode.fromJson(e as Map<String, dynamic>))
      .toList(),
  edges: (json['edges'] as List<dynamic>)
      .map((e) => CanvasEdge.fromJson(e as Map<String, dynamic>))
      .toList(),
  metadata: json['metadata'] as Map<String, dynamic>,
);

Map<String, dynamic> _$CanvasGraphToJson(CanvasGraph instance) =>
    <String, dynamic>{
      'nodes': instance.nodes,
      'edges': instance.edges,
      'metadata': instance.metadata,
    };
