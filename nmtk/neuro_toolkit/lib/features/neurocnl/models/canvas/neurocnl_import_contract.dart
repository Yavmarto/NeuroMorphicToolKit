import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';

class NeurocNlImportContract {
  const NeurocNlImportContract({
    required this.payloadType,
    required this.payloadVersion,
    required this.sourceModule,
    required this.semanticsMode,
    required this.cnlSpec,
    required this.graph,
    this.warnings = const [],
  });

  final String payloadType;
  final String payloadVersion;
  final String sourceModule;
  final String semanticsMode;
  final String cnlSpec;
  final CanvasGraph graph;
  final List<String> warnings;

  factory NeurocNlImportContract.fromJson(Map<String, dynamic> json) {
    return NeurocNlImportContract(
      payloadType: json['payload_type'] as String,
      payloadVersion: json['payload_version'] as String,
      sourceModule: json['source_module'] as String,
      semanticsMode: json['semantics_mode'] as String,
      cnlSpec: json['cnl_spec'] as String,
      graph: CanvasGraph.fromJson(
        Map<String, dynamic>.from(json['graph'] as Map),
      ),
      warnings: (json['warnings'] as List? ?? const [])
          .map((warning) => warning.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'payload_type': payloadType,
      'payload_version': payloadVersion,
      'source_module': sourceModule,
      'semantics_mode': semanticsMode,
      'cnl_spec': cnlSpec,
      'graph': graph.toJson(),
      'warnings': warnings,
    };
  }
}
