/// Response models for the Phase G deploy-target preview surface:
/// GET /api/deploy-targets and POST /api/notebook/preview.
class DeployTargetInfo {
  const DeployTargetInfo({
    required this.id,
    required this.kind,
    this.supportedNodes = const [],
    this.approximateNodes = const [],
    this.unsupportedNodes = const [],
  });

  final String id;

  /// 'simulator' (dispatchable via /simulators/run) or 'codegen' (notebook
  /// code generation only, via /notebook/generate-v2 and /notebook/preview).
  final String kind;
  final List<String> supportedNodes;
  final List<String> approximateNodes;
  final List<String> unsupportedNodes;

  factory DeployTargetInfo.fromJson(Map<String, dynamic> json) {
    List<String> stringList(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(growable: false);
    return DeployTargetInfo(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String? ?? 'codegen',
      supportedNodes: stringList('supported_nodes'),
      approximateNodes: stringList('approximate_nodes'),
      unsupportedNodes: stringList('unsupported_nodes'),
    );
  }
}

class DeployPreviewResult {
  const DeployPreviewResult({
    required this.target,
    required this.code,
    this.supportLevel,
    this.diagnostics = const [],
    this.ioError,
  });

  final String target;
  final String? supportLevel;
  final List<String> diagnostics;
  final String? ioError;
  final String code;

  factory DeployPreviewResult.fromJson(Map<String, dynamic> json) {
    return DeployPreviewResult(
      target: json['target'] as String? ?? '',
      supportLevel: json['support_level'] as String?,
      diagnostics: (json['diagnostics'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      ioError: json['io_error'] as String?,
      code: json['code'] as String? ?? '',
    );
  }
}
