// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pipeline_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PipelineState _$PipelineStateFromJson(
  Map<String, dynamic> json,
) => _PipelineState(
  parseStatus:
      $enumDecodeNullable(_$StepStatusEnumMap, json['parseStatus']) ??
      StepStatus.idle,
  validateStatus:
      $enumDecodeNullable(_$StepStatusEnumMap, json['validateStatus']) ??
      StepStatus.idle,
  generateStatus:
      $enumDecodeNullable(_$StepStatusEnumMap, json['generateStatus']) ??
      StepStatus.idle,
  simulateStatus:
      $enumDecodeNullable(_$StepStatusEnumMap, json['simulateStatus']) ??
      StepStatus.idle,
  deployReadinessStatus:
      $enumDecodeNullable(_$StepStatusEnumMap, json['deployReadinessStatus']) ??
      StepStatus.idle,
  parseResult: json['parseResult'] == null
      ? null
      : ParseResult.fromJson(json['parseResult'] as Map<String, dynamic>),
  validateResult: json['validateResult'] == null
      ? null
      : ValidationResult.fromJson(
          json['validateResult'] as Map<String, dynamic>,
        ),
  generateResult: json['generateResult'] == null
      ? null
      : GenerateResult.fromJson(json['generateResult'] as Map<String, dynamic>),
  simulateResult: json['simulateResult'] == null
      ? null
      : SimulationResult.fromJson(
          json['simulateResult'] as Map<String, dynamic>,
        ),
  deployReadinessResult: json['deployReadinessResult'] == null
      ? null
      : DeployReadinessResult.fromJson(
          json['deployReadinessResult'] as Map<String, dynamic>,
        ),
  errorMessage: json['errorMessage'] as String?,
  simulationStartTime: json['simulationStartTime'] == null
      ? null
      : DateTime.parse(json['simulationStartTime'] as String),
  requestedDuration: (json['requestedDuration'] as num?)?.toDouble(),
);

Map<String, dynamic> _$PipelineStateToJson(
  _PipelineState instance,
) => <String, dynamic>{
  'parseStatus': _$StepStatusEnumMap[instance.parseStatus]!,
  'validateStatus': _$StepStatusEnumMap[instance.validateStatus]!,
  'generateStatus': _$StepStatusEnumMap[instance.generateStatus]!,
  'simulateStatus': _$StepStatusEnumMap[instance.simulateStatus]!,
  'deployReadinessStatus': _$StepStatusEnumMap[instance.deployReadinessStatus]!,
  'parseResult': instance.parseResult,
  'validateResult': instance.validateResult,
  'generateResult': instance.generateResult,
  'simulateResult': instance.simulateResult,
  'deployReadinessResult': instance.deployReadinessResult,
  'errorMessage': instance.errorMessage,
  'simulationStartTime': instance.simulationStartTime?.toIso8601String(),
  'requestedDuration': instance.requestedDuration,
};

const _$StepStatusEnumMap = {
  StepStatus.idle: 'idle',
  StepStatus.running: 'running',
  StepStatus.success: 'success',
  StepStatus.error: 'error',
};
