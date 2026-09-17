import 'package:json_annotation/json_annotation.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';

part 'project.g.dart';

@JsonSerializable()
class ProjectSummary {
  final String id;
  final String name;
  final String description;
  @JsonKey(name: 'updated_at')
  final String updatedAt;

  ProjectSummary({
    required this.id,
    required this.name,
    this.description = '',
    required this.updatedAt,
  });

  factory ProjectSummary.fromJson(Map<String, dynamic> json) =>
      _$ProjectSummaryFromJson(json);
  Map<String, dynamic> toJson() => _$ProjectSummaryToJson(this);
}

@JsonSerializable()
class Project extends ProjectSummary {
  final CanvasGraph graph;
  @JsonKey(name: 'cnl_spec')
  final String cnlSpec;

  Project({
    required super.id,
    required super.name,
    super.description = '',
    required super.updatedAt,
    required this.graph,
    this.cnlSpec = '',
  });

  factory Project.fromJson(Map<String, dynamic> json) =>
      _$ProjectFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$ProjectToJson(this);
}

@JsonSerializable()
class CreateProjectRequest {
  final String name;
  final String description;
  final CanvasGraph graph;

  CreateProjectRequest({
    required this.name,
    this.description = '',
    required this.graph,
  });

  factory CreateProjectRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateProjectRequestFromJson(json);
  Map<String, dynamic> toJson() => _$CreateProjectRequestToJson(this);
}
