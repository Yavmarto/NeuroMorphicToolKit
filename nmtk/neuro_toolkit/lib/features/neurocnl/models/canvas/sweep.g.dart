// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sweep.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SweepRequest _$SweepRequestFromJson(Map<String, dynamic> json) => SweepRequest(
  graph: CanvasGraph.fromJson(json['graph'] as Map<String, dynamic>),
  parameterPath: json['parameter_path'] as String,
  start: (json['start'] as num).toDouble(),
  end: (json['end'] as num).toDouble(),
  steps: (json['steps'] as num).toInt(),
  simulationDurationMs:
      (json['simulation_duration_ms'] as num?)?.toDouble() ?? 500.0,
);

Map<String, dynamic> _$SweepRequestToJson(SweepRequest instance) =>
    <String, dynamic>{
      'graph': instance.graph,
      'parameter_path': instance.parameterPath,
      'start': instance.start,
      'end': instance.end,
      'steps': instance.steps,
      'simulation_duration_ms': instance.simulationDurationMs,
    };

SweepStepResult _$SweepStepResultFromJson(Map<String, dynamic> json) =>
    SweepStepResult(
      parameterValue: (json['parameter_value'] as num).toDouble(),
      result: PreviewResponse.fromJson(json['result'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$SweepStepResultToJson(SweepStepResult instance) =>
    <String, dynamic>{
      'parameter_value': instance.parameterValue,
      'result': instance.result,
    };

SweepResponse _$SweepResponseFromJson(Map<String, dynamic> json) =>
    SweepResponse(
      jobId: json['job_id'] as String?,
      status: json['status'] as String,
      error: json['error'] as String?,
      parameterPath: json['parameter_path'] as String,
      steps: (json['steps'] as List<dynamic>?)
          ?.map((e) => SweepStepResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      backendSupport: json['backend_support'] == null
          ? null
          : BackendSupport.fromJson(
              json['backend_support'] as Map<String, dynamic>,
            ),
      generatorFidelity: json['generator_fidelity'] == null
          ? null
          : GeneratorFidelitySummary.fromJson(
              json['generator_fidelity'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$SweepResponseToJson(SweepResponse instance) =>
    <String, dynamic>{
      'job_id': instance.jobId,
      'status': instance.status,
      'error': instance.error,
      'parameter_path': instance.parameterPath,
      'steps': instance.steps,
      'backend_support': instance.backendSupport,
      'generator_fidelity': instance.generatorFidelity,
    };
