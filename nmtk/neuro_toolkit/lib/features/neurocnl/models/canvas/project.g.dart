// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProjectSummary _$ProjectSummaryFromJson(Map<String, dynamic> json) =>
    ProjectSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      updatedAt: json['updated_at'] as String,
    );

Map<String, dynamic> _$ProjectSummaryToJson(ProjectSummary instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'updated_at': instance.updatedAt,
    };

Project _$ProjectFromJson(Map<String, dynamic> json) => Project(
  id: json['id'] as String,
  name: json['name'] as String,
  description: json['description'] as String? ?? '',
  updatedAt: json['updated_at'] as String,
  graph: CanvasGraph.fromJson(json['graph'] as Map<String, dynamic>),
  cnlSpec: json['cnl_spec'] as String? ?? '',
);

Map<String, dynamic> _$ProjectToJson(Project instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'description': instance.description,
  'updated_at': instance.updatedAt,
  'graph': instance.graph,
  'cnl_spec': instance.cnlSpec,
};

CreateProjectRequest _$CreateProjectRequestFromJson(
  Map<String, dynamic> json,
) => CreateProjectRequest(
  name: json['name'] as String,
  description: json['description'] as String? ?? '',
  graph: CanvasGraph.fromJson(json['graph'] as Map<String, dynamic>),
);

Map<String, dynamic> _$CreateProjectRequestToJson(
  CreateProjectRequest instance,
) => <String, dynamic>{
  'name': instance.name,
  'description': instance.description,
  'graph': instance.graph,
};
