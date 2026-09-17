/// Mirrors the backend PreflightResult Pydantic schema.
///
/// Deserialises the JSON response from both preflight endpoints:
///   POST /api/simulators/preflight
///   POST /api/simulators/preflight-nir
class PreflightResult {
  final String level; // "exact" | "approximate" | "unsupported"
  final List<String> supportedNodes;
  final List<String> approximateNodes;
  final List<String> unsupportedNodes;
  final List<String> diagnostics;

  const PreflightResult({
    required this.level,
    required this.supportedNodes,
    required this.approximateNodes,
    required this.unsupportedNodes,
    required this.diagnostics,
  });

  factory PreflightResult.fromJson(Map<String, dynamic> json) =>
      PreflightResult(
        level: json['level'] as String,
        supportedNodes: List<String>.from(
          json['supported_nodes'] as List? ?? [],
        ),
        approximateNodes: List<String>.from(
          json['approximate_nodes'] as List? ?? [],
        ),
        unsupportedNodes: List<String>.from(
          json['unsupported_nodes'] as List? ?? [],
        ),
        diagnostics: List<String>.from(json['diagnostics'] as List? ?? []),
      );
}
