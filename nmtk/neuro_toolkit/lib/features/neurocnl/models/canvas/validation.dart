import 'package:json_annotation/json_annotation.dart';

part 'validation.g.dart';

@JsonSerializable()
class BackendSupport {
  final String backend;
  final String verdict;
  @JsonKey(name: 'supported_concepts')
  final List<String> supportedConcepts;
  @JsonKey(name: 'approximated_concepts')
  final List<String> approximatedConcepts;
  @JsonKey(name: 'unsupported_concepts')
  final List<String> unsupportedConcepts;
  final List<String> warnings;

  BackendSupport({
    required this.backend,
    required this.verdict,
    this.supportedConcepts = const [],
    this.approximatedConcepts = const [],
    this.unsupportedConcepts = const [],
    this.warnings = const [],
  });

  factory BackendSupport.fromJson(Map<String, dynamic> json) =>
      _$BackendSupportFromJson(json);
  Map<String, dynamic> toJson() => _$BackendSupportToJson(this);
}

@JsonSerializable()
class GeneratorFidelityAnnotation {
  final String concept;
  final String subject;
  final String fidelity;
  final String reason;

  GeneratorFidelityAnnotation({
    required this.concept,
    required this.subject,
    required this.fidelity,
    required this.reason,
  });

  factory GeneratorFidelityAnnotation.fromJson(Map<String, dynamic> json) =>
      _$GeneratorFidelityAnnotationFromJson(json);
  Map<String, dynamic> toJson() => _$GeneratorFidelityAnnotationToJson(this);
}

@JsonSerializable()
class GeneratorFidelitySummary {
  final List<GeneratorFidelityAnnotation> annotations;

  GeneratorFidelitySummary({this.annotations = const []});

  factory GeneratorFidelitySummary.fromJson(Map<String, dynamic> json) =>
      _$GeneratorFidelitySummaryFromJson(json);
  Map<String, dynamic> toJson() => _$GeneratorFidelitySummaryToJson(this);
}

@JsonSerializable()
class ValidationError {
  @JsonKey(name: 'element_id')
  final String elementId;
  final String field;
  final String message;
  final String severity;

  ValidationError({
    required this.elementId,
    required this.field,
    required this.message,
    this.severity = 'error',
  });

  factory ValidationError.fromJson(Map<String, dynamic> json) =>
      _$ValidationErrorFromJson(json);
  Map<String, dynamic> toJson() => _$ValidationErrorToJson(this);
}

@JsonSerializable()
class ValidationResult {
  final bool valid;
  final List<ValidationError> errors;
  @JsonKey(name: 'backend_support')
  final BackendSupport? backendSupport;
  @JsonKey(name: 'generator_fidelity')
  final GeneratorFidelitySummary? generatorFidelity;

  ValidationResult({
    required this.valid,
    required this.errors,
    this.backendSupport,
    this.generatorFidelity,
  });

  factory ValidationResult.fromJson(Map<String, dynamic> json) =>
      _$ValidationResultFromJson(json);
  Map<String, dynamic> toJson() => _$ValidationResultToJson(this);
}
