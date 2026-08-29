import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_config.dart';

/// Result of `POST /api/notebook/generate-pipeline-cnl`.
///
/// Renders the current [PipelineConfig] as CNL text, for display in the
/// Pipeline tab's CNL preview panel.
class PipelineCnlResult {
  const PipelineCnlResult({required this.cnlText, this.diagnostics = const []});

  final String cnlText;
  final List<String> diagnostics;

  factory PipelineCnlResult.fromJson(Map<String, dynamic> json) =>
      PipelineCnlResult(
        cnlText: json['cnl_text'] as String? ?? '',
        diagnostics:
            (json['diagnostics'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

/// Result of `POST /api/notebook/parse-pipeline-cnl`.
///
/// [pipelineConfig] is the caller's base config with only the fields the
/// CNL text specifies overridden — every other field is unchanged.
class PipelineConfigParseResult {
  const PipelineConfigParseResult({
    required this.pipelineConfig,
    this.diagnostics = const [],
  });

  final PipelineConfig pipelineConfig;
  final List<String> diagnostics;

  factory PipelineConfigParseResult.fromJson(Map<String, dynamic> json) =>
      PipelineConfigParseResult(
        pipelineConfig: PipelineConfig.fromJson(
          json['pipeline_config'] as Map<String, dynamic>,
        ),
        diagnostics:
            (json['diagnostics'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}
