// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'component.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PortDef _$PortDefFromJson(Map<String, dynamic> json) => PortDef(
  id: json['id'] as String,
  direction: json['direction'] as String,
  label: json['label'] as String,
);

Map<String, dynamic> _$PortDefToJson(PortDef instance) => <String, dynamic>{
  'id': instance.id,
  'direction': instance.direction,
  'label': instance.label,
};

ParameterDef _$ParameterDefFromJson(Map<String, dynamic> json) => ParameterDef(
  name: json['name'] as String,
  label: json['label'] as String,
  description: json['description'] as String,
  type: json['type'] as String,
  defaultValue: json['default'],
  min: (json['min'] as num?)?.toDouble(),
  max: (json['max'] as num?)?.toDouble(),
  unit: json['unit'] as String?,
  enumValues: (json['enum_values'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
);

Map<String, dynamic> _$ParameterDefToJson(ParameterDef instance) =>
    <String, dynamic>{
      'name': instance.name,
      'label': instance.label,
      'description': instance.description,
      'type': instance.type,
      'default': instance.defaultValue,
      'min': instance.min,
      'max': instance.max,
      'unit': instance.unit,
      'enum_values': instance.enumValues,
    };

ComponentBlock _$ComponentBlockFromJson(Map<String, dynamic> json) =>
    ComponentBlock(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      description: json['description'] as String,
      icon: json['icon'] as String,
      parameters: (json['parameters'] as List<dynamic>)
          .map((e) => ParameterDef.fromJson(e as Map<String, dynamic>))
          .toList(),
      ports: (json['ports'] as List<dynamic>)
          .map((e) => PortDef.fromJson(e as Map<String, dynamic>))
          .toList(),
      cnlTemplate: json['cnl_template'] as String,
      isCustom: json['is_custom'] as bool? ?? false,
      sourceFilename: json['source_filename'] as String?,
      sourceAvailable: json['source_available'] as bool? ?? false,
      baseComponentId: json['base_component_id'] as String?,
      baseNirType: json['base_nir_type'] as String?,
      basePipelineType: json['base_pipeline_type'] as String?,
      canvasContexts:
          (json['canvas_contexts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      supportedFrameworks:
          (json['supported_frameworks'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      author: json['author'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
    );

Map<String, dynamic> _$ComponentBlockToJson(ComponentBlock instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'category': instance.category,
      'description': instance.description,
      'icon': instance.icon,
      'parameters': instance.parameters,
      'ports': instance.ports,
      'cnl_template': instance.cnlTemplate,
      'is_custom': instance.isCustom,
      'source_filename': instance.sourceFilename,
      'source_available': instance.sourceAvailable,
      'base_component_id': instance.baseComponentId,
      'base_nir_type': instance.baseNirType,
      'base_pipeline_type': instance.basePipelineType,
      'canvas_contexts': instance.canvasContexts,
      'supported_frameworks': instance.supportedFrameworks,
      'author': instance.author,
      'version': instance.version,
    };
