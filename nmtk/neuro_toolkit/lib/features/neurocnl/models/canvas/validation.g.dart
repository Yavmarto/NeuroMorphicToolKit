// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'validation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BackendSupport _$BackendSupportFromJson(Map<String, dynamic> json) =>
    BackendSupport(
      backend: json['backend'] as String,
      verdict: json['verdict'] as String,
      supportedConcepts:
          (json['supported_concepts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      approximatedConcepts:
          (json['approximated_concepts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      unsupportedConcepts:
          (json['unsupported_concepts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      warnings:
          (json['warnings'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );

Map<String, dynamic> _$BackendSupportToJson(BackendSupport instance) =>
    <String, dynamic>{
      'backend': instance.backend,
      'verdict': instance.verdict,
      'supported_concepts': instance.supportedConcepts,
      'approximated_concepts': instance.approximatedConcepts,
      'unsupported_concepts': instance.unsupportedConcepts,
      'warnings': instance.warnings,
    };

GeneratorFidelityAnnotation _$GeneratorFidelityAnnotationFromJson(
  Map<String, dynamic> json,
) => GeneratorFidelityAnnotation(
  concept: json['concept'] as String,
  subject: json['subject'] as String,
  fidelity: json['fidelity'] as String,
  reason: json['reason'] as String,
);

Map<String, dynamic> _$GeneratorFidelityAnnotationToJson(
  GeneratorFidelityAnnotation instance,
) => <String, dynamic>{
  'concept': instance.concept,
  'subject': instance.subject,
  'fidelity': instance.fidelity,
  'reason': instance.reason,
};

GeneratorFidelitySummary _$GeneratorFidelitySummaryFromJson(
  Map<String, dynamic> json,
) => GeneratorFidelitySummary(
  annotations:
      (json['annotations'] as List<dynamic>?)
          ?.map(
            (e) =>
                GeneratorFidelityAnnotation.fromJson(e as Map<String, dynamic>),
          )
          .toList() ??
      const [],
);

Map<String, dynamic> _$GeneratorFidelitySummaryToJson(
  GeneratorFidelitySummary instance,
) => <String, dynamic>{'annotations': instance.annotations};

ValidationError _$ValidationErrorFromJson(Map<String, dynamic> json) =>
    ValidationError(
      elementId: json['element_id'] as String,
      field: json['field'] as String,
      message: json['message'] as String,
      severity: json['severity'] as String? ?? 'error',
    );

Map<String, dynamic> _$ValidationErrorToJson(ValidationError instance) =>
    <String, dynamic>{
      'element_id': instance.elementId,
      'field': instance.field,
      'message': instance.message,
      'severity': instance.severity,
    };

ValidationResult _$ValidationResultFromJson(Map<String, dynamic> json) =>
    ValidationResult(
      valid: json['valid'] as bool,
      errors: (json['errors'] as List<dynamic>)
          .map((e) => ValidationError.fromJson(e as Map<String, dynamic>))
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

Map<String, dynamic> _$ValidationResultToJson(ValidationResult instance) =>
    <String, dynamic>{
      'valid': instance.valid,
      'errors': instance.errors,
      'backend_support': instance.backendSupport,
      'generator_fidelity': instance.generatorFidelity,
    };
