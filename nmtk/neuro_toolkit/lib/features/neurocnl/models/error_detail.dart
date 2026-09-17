class ErrorDetail {
  final String? code;
  final String? message;
  final String? hint;
  final List<String> examples;
  final int? line;
  final String? raw;
  final String? source;
  final String? field;
  final Object? value;
  final List<int> lines;
  final String? name;
  final String? reason;
  final String? check;
  final String? detail;
  final bool? result;
  final String? description;
  final String? severity;

  const ErrorDetail({
    this.code,
    this.message,
    this.hint,
    this.examples = const [],
    this.line,
    this.raw,
    this.source,
    this.field,
    this.value,
    this.lines = const [],
    this.name,
    this.reason,
    this.check,
    this.detail,
    this.result,
    this.description,
    this.severity,
  });

  String? get primaryCode => code ?? check ?? name;

  String? get primaryMessage => message ?? detail ?? reason ?? description;

  factory ErrorDetail.fromJson(Map<String, dynamic> json) {
    return ErrorDetail(
      code: (json['code'] ?? json['check'] ?? json['name']) as String?,
      message:
          (json['message'] ??
                  json['detail'] ??
                  json['reason'] ??
                  json['description'])
              as String?,
      hint: json['hint'] as String?,
      examples: (json['examples'] as List?)?.cast<String>() ?? const [],
      line: json['line'] as int?,
      raw: json['raw'] as String?,
      source: json['source'] as String?,
      field: json['field'] as String?,
      value: json['value'],
      lines: (json['lines'] as List?)?.cast<int>() ?? const [],
      name: json['name'] as String?,
      reason: json['reason'] as String?,
      check: json['check'] as String?,
      detail: json['detail'] as String?,
      result: json['result'] as bool?,
      description: json['description'] as String?,
      severity: json['severity'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    'hint': hint,
    'examples': examples,
    'line': line,
    'raw': raw,
    'source': source,
    'field': field,
    'value': value,
    'lines': lines,
    'name': name,
    'reason': reason,
    'check': check,
    'detail': detail,
    'result': result,
    'description': description,
    'severity': severity,
  };
}
