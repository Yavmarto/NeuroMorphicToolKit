/// A single failed check in Layer 2 validation.
class Layer2Check {
  final String? name;
  final String? description;
  final String? error;
  final String? code;
  final String? message;
  final String? hint;
  final List<String> examples;
  final List<int> lines;
  final Map<String, dynamic> params;

  const Layer2Check({
    this.name,
    this.description,
    this.error,
    this.code,
    this.message,
    this.hint,
    this.examples = const [],
    this.lines = const [],
    required this.params,
  });

  String? get primaryName => code ?? name;

  String? get primaryMessage => message ?? description ?? error;

  factory Layer2Check.fromJson(Map<String, dynamic> json) {
    return Layer2Check(
      name: (json['name'] ?? json['check']) as String?,
      description:
          (json['message'] ??
                  json['detail'] ??
                  json['reason'] ??
                  json['description'])
              as String?,
      error: json['error'] as String?,
      code: (json['code'] ?? json['check'] ?? json['name']) as String?,
      message:
          (json['message'] ??
                  json['detail'] ??
                  json['reason'] ??
                  json['description'])
              as String?,
      hint: json['hint'] as String?,
      examples: (json['examples'] as List?)?.cast<String>() ?? const [],
      lines: (json['lines'] as List?)?.cast<int>() ?? const [],
      params: Map<String, dynamic>.from(json),
    );
  }
}
