import 'package:neuro_toolkit/features/neurocnl/models/layer2_check.dart';

class BackendSupportResult {
  final String backend;
  final String verdict;
  final List<String> supportedConcepts;
  final List<String> approximatedConcepts;
  final List<String> unsupportedConcepts;
  final List<String> warnings;

  const BackendSupportResult({
    required this.backend,
    required this.verdict,
    this.supportedConcepts = const [],
    this.approximatedConcepts = const [],
    this.unsupportedConcepts = const [],
    this.warnings = const [],
  });

  factory BackendSupportResult.fromJson(Map<String, dynamic> json) {
    return BackendSupportResult(
      backend: json['backend'] as String,
      verdict: json['verdict'] as String,
      supportedConcepts:
          (json['supported_concepts'] as List?)?.cast<String>() ?? const [],
      approximatedConcepts:
          (json['approximated_concepts'] as List?)?.cast<String>() ?? const [],
      unsupportedConcepts:
          (json['unsupported_concepts'] as List?)?.cast<String>() ?? const [],
      warnings: (json['warnings'] as List?)?.cast<String>() ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'backend': backend,
    'verdict': verdict,
    'supported_concepts': supportedConcepts,
    'approximated_concepts': approximatedConcepts,
    'unsupported_concepts': unsupportedConcepts,
    'warnings': warnings,
  };
}

/// Result of a single Layer 1 invariant check.
class InvariantResult {
  final String name;
  final String description;
  final bool result;
  final String? code;
  final String? message;
  final String? hint;
  final List<String> examples;
  final int? line;
  final String? source;
  final String? field;
  final Object? value;
  final List<int> lines;
  final String? raw;
  final String? severity;

  const InvariantResult({
    required this.name,
    required this.description,
    required this.result,
    this.code,
    this.message,
    this.hint,
    this.examples = const [],
    this.line,
    this.source,
    this.field,
    this.value,
    this.lines = const [],
    this.raw,
    this.severity,
  });

  factory InvariantResult.fromJson(Map<String, dynamic> json) {
    return InvariantResult(
      name: (json['name'] ?? json['code']) as String,
      description:
          (json['message'] ?? json['reason'] ?? json['description']) as String,
      result: json['result'] as bool? ?? true,
      code: json['code'] as String?,
      message: json['message'] as String?,
      hint: json['hint'] as String?,
      examples: (json['examples'] as List?)?.cast<String>() ?? const [],
      line: json['line'] as int?,
      source: json['source'] as String?,
      field: json['field'] as String?,
      value: json['value'],
      lines: (json['lines'] as List?)?.cast<int>() ?? const [],
      raw: json['raw'] as String?,
      severity: json['severity'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'result': result,
    'code': code,
    'message': message,
    'hint': hint,
    'examples': examples,
    'line': line,
    'source': source,
    'field': field,
    'value': value,
    'lines': lines,
    'raw': raw,
    'severity': severity,
  };
}

/// Layer 1 validation result.
class Layer1Result {
  final bool overall;
  final List<InvariantResult> passed;
  final List<InvariantResult> failed;
  final List<InvariantResult> warnings;

  const Layer1Result({
    required this.overall,
    required this.passed,
    required this.failed,
    this.warnings = const [],
  });

  factory Layer1Result.fromJson(Map<String, dynamic> json) {
    return Layer1Result(
      overall: json['overall'] as bool,
      passed: (json['passed'] as List)
          .map((p) => InvariantResult.fromJson(p as Map<String, dynamic>))
          .toList(),
      failed: (json['failed'] as List)
          .map((f) => InvariantResult.fromJson(f as Map<String, dynamic>))
          .toList(),
      warnings: (json['warnings'] as List? ?? const [])
          .map((w) => InvariantResult.fromJson(w as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'overall': overall,
    'passed': passed.map((p) => p.toJson()).toList(),
    'failed': failed.map((f) => f.toJson()).toList(),
    'warnings': warnings.map((w) => w.toJson()).toList(),
  };
}

/// Layer 2 validation result.
class Layer2Result {
  final bool overall;
  final List<String> checksPassed;
  final List<Layer2Check> checksFailed;
  final List<String> neuronsFound;

  const Layer2Result({
    required this.overall,
    required this.checksPassed,
    required this.checksFailed,
    required this.neuronsFound,
  });

  factory Layer2Result.fromJson(Map<String, dynamic> json) {
    return Layer2Result(
      overall: json['overall'] as bool,
      checksPassed: (json['checks_passed'] as List).cast<String>(),
      checksFailed: (json['checks_failed'] as List)
          .map((c) => Layer2Check.fromJson(c as Map<String, dynamic>))
          .toList(),
      neuronsFound: (json['neurons_found'] as List).cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
    'overall': overall,
    'checks_passed': checksPassed,
    'checks_failed': checksFailed.map((c) => c.params).toList(),
    'neurons_found': neuronsFound,
  };
}

/// Combined validation response.
class ValidationResult {
  final Layer1Result layer1;
  final Layer2Result layer2;
  final bool overall;
  final BackendSupportResult? backendSupport;

  const ValidationResult({
    required this.layer1,
    required this.layer2,
    required this.overall,
    this.backendSupport,
  });

  factory ValidationResult.fromJson(Map<String, dynamic> json) {
    return ValidationResult(
      layer1: Layer1Result.fromJson(json['layer1'] as Map<String, dynamic>),
      layer2: Layer2Result.fromJson(json['layer2'] as Map<String, dynamic>),
      overall: json['overall'] as bool,
      backendSupport: json['backend_support'] != null
          ? BackendSupportResult.fromJson(
              json['backend_support'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'layer1': layer1.toJson(),
    'layer2': layer2.toJson(),
    'overall': overall,
    'backend_support': backendSupport?.toJson(),
  };
}
