// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'deploy_readiness_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeployReadinessOk _$DeployReadinessOkFromJson(Map<String, dynamic> json) =>
    DeployReadinessOk($type: json['status'] as String?);

Map<String, dynamic> _$DeployReadinessOkToJson(DeployReadinessOk instance) =>
    <String, dynamic>{'status': instance.$type};

DeployReadinessUnsupported _$DeployReadinessUnsupportedFromJson(
  Map<String, dynamic> json,
) => DeployReadinessUnsupported(
  level: json['level'] as String,
  unsupportedNodes: (json['unsupportedNodes'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  diagnostics: (json['diagnostics'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  $type: json['status'] as String?,
);

Map<String, dynamic> _$DeployReadinessUnsupportedToJson(
  DeployReadinessUnsupported instance,
) => <String, dynamic>{
  'level': instance.level,
  'unsupportedNodes': instance.unsupportedNodes,
  'diagnostics': instance.diagnostics,
  'status': instance.$type,
};

DeployReadinessError _$DeployReadinessErrorFromJson(
  Map<String, dynamic> json,
) => DeployReadinessError(
  message: json['message'] as String,
  $type: json['status'] as String?,
);

Map<String, dynamic> _$DeployReadinessErrorToJson(
  DeployReadinessError instance,
) => <String, dynamic>{'message': instance.message, 'status': instance.$type};
