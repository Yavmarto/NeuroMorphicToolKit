import 'package:json_annotation/json_annotation.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/preview.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';

part 'sweep.g.dart';

@JsonSerializable()
class SweepRequest {
  final CanvasGraph graph;
  @JsonKey(name: 'parameter_path')
  final String parameterPath;
  final double start;
  final double end;
  final int steps;
  @JsonKey(name: 'simulation_duration_ms')
  final double simulationDurationMs;

  SweepRequest({
    required this.graph,
    required this.parameterPath,
    required this.start,
    required this.end,
    required this.steps,
    this.simulationDurationMs = 500.0,
  });

  factory SweepRequest.fromJson(Map<String, dynamic> json) =>
      _$SweepRequestFromJson(json);
  Map<String, dynamic> toJson() => _$SweepRequestToJson(this);
}

@JsonSerializable()
class SweepStepResult {
  @JsonKey(name: 'parameter_value')
  final double parameterValue;
  final PreviewResponse result;

  SweepStepResult({required this.parameterValue, required this.result});

  factory SweepStepResult.fromJson(Map<String, dynamic> json) =>
      _$SweepStepResultFromJson(json);
  Map<String, dynamic> toJson() => _$SweepStepResultToJson(this);
}

@JsonSerializable()
class SweepResponse {
  @JsonKey(name: 'job_id')
  final String? jobId;
  final String status;
  final String? error;
  @JsonKey(name: 'parameter_path')
  final String parameterPath;
  final List<SweepStepResult>? steps;
  @JsonKey(name: 'backend_support')
  final BackendSupport? backendSupport;
  @JsonKey(name: 'generator_fidelity')
  final GeneratorFidelitySummary? generatorFidelity;

  SweepResponse({
    this.jobId,
    required this.status,
    this.error,
    required this.parameterPath,
    this.steps,
    this.backendSupport,
    this.generatorFidelity,
  });

  factory SweepResponse.fromJson(Map<String, dynamic> json) =>
      _$SweepResponseFromJson(json);
  Map<String, dynamic> toJson() => _$SweepResponseToJson(this);
}
