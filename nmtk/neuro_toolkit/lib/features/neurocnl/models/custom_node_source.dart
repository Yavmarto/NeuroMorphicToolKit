import 'package:neuro_toolkit/features/neurocnl/models/canvas/component.dart';

class CustomNodeDiagnostic {
  const CustomNodeDiagnostic({
    required this.message,
    required this.severity,
    required this.line,
    required this.column,
    required this.code,
    this.endLine,
    this.endColumn,
  });

  factory CustomNodeDiagnostic.fromJson(Map<String, dynamic> json) {
    return CustomNodeDiagnostic(
      message: json['message'] as String? ?? 'Unknown Python diagnostic.',
      severity: json['severity'] as String? ?? 'error',
      line: json['line'] as int? ?? 1,
      column: json['column'] as int? ?? 1,
      endLine: json['end_line'] as int?,
      endColumn: json['end_column'] as int?,
      code: json['code'] as String? ?? 'custom-node',
    );
  }

  final String message;
  final String severity;
  final int line;
  final int column;
  final int? endLine;
  final int? endColumn;
  final String code;

  bool get isError => severity == 'error';
}

class CustomNodeSource {
  const CustomNodeSource({
    required this.source,
    required this.componentId,
    required this.isCustom,
    required this.saveMode,
    this.filename,
    this.revision,
  });

  factory CustomNodeSource.fromJson(Map<String, dynamic> json) {
    return CustomNodeSource(
      source: json['source'] as String? ?? '',
      componentId: json['component_id'] as String? ?? '',
      isCustom: json['is_custom'] as bool? ?? false,
      saveMode: json['save_mode'] as String? ?? 'create',
      filename: json['filename'] as String?,
      revision: json['revision'] as String?,
    );
  }

  final String source;
  final String componentId;
  final bool isCustom;
  final String saveMode;
  final String? filename;
  final String? revision;
}

class CustomNodeValidation {
  const CustomNodeValidation({
    required this.valid,
    required this.diagnostics,
    this.component,
  });

  factory CustomNodeValidation.fromJson(Map<String, dynamic> json) {
    final diagnostics = json['diagnostics'] as List<dynamic>? ?? const [];
    final componentJson = json['component'];
    return CustomNodeValidation(
      valid: json['valid'] as bool? ?? false,
      diagnostics: diagnostics
          .map(
            (dynamic item) =>
                CustomNodeDiagnostic.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      component: componentJson is Map<String, dynamic>
          ? ComponentBlock.fromJson(componentJson)
          : null,
    );
  }

  final bool valid;
  final List<CustomNodeDiagnostic> diagnostics;
  final ComponentBlock? component;
}

class CustomNodeSaveResult {
  const CustomNodeSaveResult({
    required this.filename,
    required this.componentId,
    required this.source,
    this.revision,
    this.component,
  });

  factory CustomNodeSaveResult.fromJson(Map<String, dynamic> json) {
    final componentJson = json['component'];
    return CustomNodeSaveResult(
      filename: json['filename'] as String? ?? '',
      componentId: json['component_id'] as String? ?? '',
      source: json['source'] as String? ?? '',
      revision: json['revision'] as String?,
      component: componentJson is Map<String, dynamic>
          ? ComponentBlock.fromJson(componentJson)
          : null,
    );
  }

  final String filename;
  final String componentId;
  final String source;
  final String? revision;
  final ComponentBlock? component;
}
