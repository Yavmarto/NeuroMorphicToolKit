import 'package:json_annotation/json_annotation.dart';

part 'component.g.dart';

@JsonSerializable()
class PortDef {
  final String id;
  final String direction; // 'input' or 'output'
  final String label;

  PortDef({required this.id, required this.direction, required this.label});

  factory PortDef.fromJson(Map<String, dynamic> json) =>
      _$PortDefFromJson(json);
  Map<String, dynamic> toJson() => _$PortDefToJson(this);
}

@JsonSerializable()
class ParameterDef {
  final String name;
  final String label;
  final String description;
  final String type; // 'float', 'int', 'bool', 'enum'
  @JsonKey(name: 'default')
  final dynamic defaultValue;
  final double? min;
  final double? max;
  final String? unit;
  @JsonKey(name: 'enum_values')
  final List<String>? enumValues;

  ParameterDef({
    required this.name,
    required this.label,
    required this.description,
    required this.type,
    required this.defaultValue,
    this.min,
    this.max,
    this.unit,
    this.enumValues,
  });

  factory ParameterDef.fromJson(Map<String, dynamic> json) =>
      _$ParameterDefFromJson(json);
  Map<String, dynamic> toJson() => _$ParameterDefToJson(this);
}

@JsonSerializable()
class ComponentBlock {
  final String id;
  final String name;
  final String category;
  final String description;
  final String icon;
  final List<ParameterDef> parameters;
  final List<PortDef> ports;
  @JsonKey(name: 'cnl_template')
  final String cnlTemplate;
  @JsonKey(name: 'is_custom')
  final bool isCustom;
  @JsonKey(name: 'source_filename')
  final String? sourceFilename;
  @JsonKey(name: 'source_available')
  final bool sourceAvailable;
  @JsonKey(name: 'base_component_id')
  final String? baseComponentId;
  @JsonKey(name: 'base_nir_type')
  final String? baseNirType;
  @JsonKey(name: 'base_pipeline_type')
  final String? basePipelineType;
  @JsonKey(name: 'canvas_contexts')
  final List<String> canvasContexts;
  @JsonKey(name: 'supported_frameworks')
  final List<String> supportedFrameworks;
  final String author;
  final String version;

  ComponentBlock({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.icon,
    required this.parameters,
    required this.ports,
    required this.cnlTemplate,
    this.isCustom = false,
    this.sourceFilename,
    this.sourceAvailable = false,
    this.baseComponentId,
    this.baseNirType,
    this.basePipelineType,
    this.canvasContexts = const <String>[],
    this.supportedFrameworks = const <String>[],
    this.author = '',
    this.version = '1.0.0',
  });

  factory ComponentBlock.fromJson(Map<String, dynamic> json) =>
      _$ComponentBlockFromJson(json);
  Map<String, dynamic> toJson() => _$ComponentBlockToJson(this);
}

extension ComponentBlockX on ComponentBlock {
  bool get isSynapse => category.toLowerCase() == 'synapses';

  Map<String, dynamic> get defaultParameterValues => {
    for (final parameter in parameters) parameter.name: parameter.defaultValue,
  };
}
