import 'package:neuro_toolkit/features/neurocnl/models/error_detail.dart';

/// A single parsed CNL specification line.
class ParsedSpec {
  final String concept;
  final String subject;
  final String action;
  final String verb;
  final bool negated;
  final String? condition;

  const ParsedSpec({
    required this.concept,
    required this.subject,
    required this.action,
    required this.verb,
    required this.negated,
    this.condition,
  });

  factory ParsedSpec.fromJson(Map<String, dynamic> json) {
    return ParsedSpec(
      concept: json['concept'] as String,
      subject: json['subject'] as String,
      action: json['action'] as String,
      verb: json['verb'] as String,
      negated: json['negated'] as bool,
      condition: json['condition'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'concept': concept,
    'subject': subject,
    'action': action,
    'verb': verb,
    'negated': negated,
    'condition': condition,
  };
}

/// One sentence of the parse result (valid or invalid).
class ParseSentence {
  final int line;
  final String raw;
  final ParsedSpec? parsed;
  final bool valid;
  final String? error;
  final ErrorDetail? errorDetail;

  const ParseSentence({
    required this.line,
    required this.raw,
    this.parsed,
    required this.valid,
    this.error,
    this.errorDetail,
  });

  factory ParseSentence.fromJson(Map<String, dynamic> json) {
    return ParseSentence(
      line: json['line'] as int,
      raw: json['raw'] as String,
      parsed: json['parsed'] != null
          ? ParsedSpec.fromJson(json['parsed'] as Map<String, dynamic>)
          : null,
      valid: json['valid'] as bool,
      error: json['error'] as String?,
      errorDetail: json['error_detail'] != null
          ? ErrorDetail.fromJson(json['error_detail'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'line': line,
    'raw': raw,
    'parsed': parsed?.toJson(),
    'valid': valid,
    'error': error,
    'error_detail': errorDetail?.toJson(),
  };
}

/// Full parse response from the API.
class ParseResult {
  final List<ParseSentence> sentences;
  final int total;
  final int errors;

  const ParseResult({
    required this.sentences,
    required this.total,
    required this.errors,
  });

  factory ParseResult.fromJson(Map<String, dynamic> json) {
    return ParseResult(
      sentences: (json['sentences'] as List)
          .map((s) => ParseSentence.fromJson(s as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      errors: json['errors'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'sentences': sentences.map((s) => s.toJson()).toList(),
    'total': total,
    'errors': errors,
  };
}
