/// Fidelity annotation attached to a CNL concept, indicating how faithfully
/// the concept is represented in the canonical IR.
class FidelityAnnotation {
  const FidelityAnnotation({
    required this.kind,
    required this.concept,
    required this.message,
    this.affects = const [],
  });

  /// One of "executable", "advisory", "unsupported".
  final String kind;
  final String concept;
  final String message;

  /// List of node/edge ids or concept names affected by this annotation.
  final List<String> affects;

  factory FidelityAnnotation.fromJson(Map<String, dynamic> json) {
    return FidelityAnnotation(
      kind: json['kind'] as String,
      concept: json['concept'] as String,
      message: json['message'] as String,
      affects: (json['affects'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind,
    'concept': concept,
    'message': message,
    'affects': affects,
  };
}

/// A population node in the canvas projection derived from the canonical IR.
class CanvasNode {
  const CanvasNode({
    required this.id,
    required this.label,
    this.nirType,
    this.type = 'excitatory',
    this.size = 1,
    this.shape,
    this.threshold,
    this.tau,
    this.parameters = const <String, dynamic>{},
    this.metadata = const <String, dynamic>{},
  });

  final String id;
  final String label;

  /// NIR primitive type, e.g. 'nir.LIF', 'nir.Input', 'nir.CubaLIF'.
  /// Null when the backend did not emit a nir_type (pre-fix backend).
  final String? nirType;

  /// Population type, e.g. "excitatory" or "inhibitory".
  final String type;

  /// Number of neurons in the population.
  final int size;

  /// Optional layer shape, e.g. [28, 28].
  final List<int>? shape;

  /// Optional membrane threshold.
  final double? threshold;

  /// Optional membrane time constant.
  final double? tau;

  /// Optional backend-provided node parameters preserved for canvas import.
  final Map<String, dynamic> parameters;

  /// Optional backend-provided node metadata such as canvas category.
  final Map<String, dynamic> metadata;

  factory CanvasNode.fromJson(Map<String, dynamic> json) {
    return CanvasNode(
      id: json['id'] as String,
      label: json['label'] as String,
      nirType: json['nir_type'] as String?,
      type: json['type'] as String? ?? 'excitatory',
      size: (json['size'] as num?)?.toInt() ?? 1,
      shape: (json['shape'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      threshold: (json['threshold'] as num?)?.toDouble(),
      tau: (json['tau'] as num?)?.toDouble(),
      parameters: Map<String, dynamic>.from(
        json['parameters'] as Map? ?? const <String, dynamic>{},
      ),
      metadata: Map<String, dynamic>.from(
        json['metadata'] as Map? ?? const <String, dynamic>{},
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'label': label,
    if (nirType != null) 'nir_type': nirType,
    'type': type,
    'size': size,
    if (shape != null) 'shape': shape,
    if (threshold != null) 'threshold': threshold,
    if (tau != null) 'tau': tau,
    if (parameters.isNotEmpty) 'parameters': parameters,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

/// A connection edge in the canvas projection derived from the canonical IR.
class CanvasEdge {
  const CanvasEdge({
    required this.source,
    required this.target,
    this.polarity = 'excitatory',
    this.weight,
    this.connectivityPattern,
    this.hasLearningRule = false,
    this.learningRuleKind,
  });

  final String source;
  final String target;

  /// Polarity of the synapse, e.g. "excitatory" or "inhibitory".
  final String polarity;

  /// Optional synaptic weight.
  final double? weight;

  /// Optional connectivity pattern, e.g. "all_to_all" or "one_to_one".
  final String? connectivityPattern;

  /// Whether a plasticity/learning rule is attached to this edge.
  final bool hasLearningRule;

  /// The kind of learning rule, e.g. "stdp", "hebbian", "surrogate_gradient".
  /// Null when [hasLearningRule] is false.
  final String? learningRuleKind;

  factory CanvasEdge.fromJson(Map<String, dynamic> json) {
    return CanvasEdge(
      source: json['source'] as String,
      target: json['target'] as String,
      polarity: json['polarity'] as String? ?? 'excitatory',
      weight: (json['weight'] as num?)?.toDouble(),
      connectivityPattern: json['connectivity_pattern'] as String?,
      hasLearningRule: json['has_learning_rule'] as bool? ?? false,
      learningRuleKind: json['learning_rule_kind'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'source': source,
    'target': target,
    'polarity': polarity,
    if (weight != null) 'weight': weight,
    if (connectivityPattern != null)
      'connectivity_pattern': connectivityPattern,
    if (hasLearningRule) 'has_learning_rule': hasLearningRule,
    if (learningRuleKind != null) 'learning_rule_kind': learningRuleKind,
  };
}

/// Canvas-ready projection of the canonical IR, suitable for rendering the
/// interactive network editor without lossy re-parsing.
class CanvasProjection {
  const CanvasProjection({
    this.nodes = const [],
    this.edges = const [],
    this.readOnlyAnnotations = const [],
    this.metadata = const <String, dynamic>{},
  });

  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;

  /// Annotations that apply to the overall canvas layout (not editable).
  final List<FidelityAnnotation> readOnlyAnnotations;

  /// Graph-level metadata, e.g. a declared network timestep (`'dt'`,
  /// seconds) from the nir_cnl grammar's optional
  /// `with timestep <seconds>` clause.
  final Map<String, dynamic> metadata;

  factory CanvasProjection.fromJson(Map<String, dynamic> json) {
    return CanvasProjection(
      nodes: (json['nodes'] as List<dynamic>? ?? const [])
          .map((e) => CanvasNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      edges: (json['edges'] as List<dynamic>? ?? const [])
          .map((e) => CanvasEdge.fromJson(e as Map<String, dynamic>))
          .toList(),
      readOnlyAnnotations:
          (json['read_only_annotations'] as List<dynamic>? ?? const [])
              .map(
                (e) => FidelityAnnotation.fromJson(e as Map<String, dynamic>),
              )
              .toList(),
      metadata: Map<String, dynamic>.from(
        json['metadata'] as Map? ?? const <String, dynamic>{},
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'edges': edges.map((e) => e.toJson()).toList(),
    'read_only_annotations': readOnlyAnnotations
        .map((a) => a.toJson())
        .toList(),
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

/// The canonical editor document — the single source of truth that ties together
/// the CNL text, the backend IR JSON, fidelity annotations, and the canvas
/// projection. Mirrors the backend `CanonicalEditorDocument` Pydantic contract.
String _sanitizeLegacyTensorValueClauses(String cnlText) {
  if (!cnlText.contains('weight matrix values') &&
      !cnlText.contains('weight kernel values')) {
    return cnlText;
  }
  return cnlText
      .replaceAll(RegExp(r' and weight matrix values \([^)]*\)'), '')
      .replaceAll(RegExp(r', weight matrix values \([^)]*\)'), '')
      .replaceAll(RegExp(r' and weight kernel values \([^)]*\)'), '')
      .replaceAll(RegExp(r', weight kernel values \([^)]*\)'), '');
}

class CanonicalEditorDocument {
  const CanonicalEditorDocument({
    required this.irJson,
    this.cnlText = '',
    this.fidelityAnnotations = const [],
    this.canvas,
  });

  /// Raw intermediate-representation JSON produced by the backend parser.
  final Map<String, dynamic> irJson;

  /// CNL source text corresponding to this document.
  final String cnlText;

  /// Suite-wide fidelity annotations for the document.
  final List<FidelityAnnotation> fidelityAnnotations;

  /// Optional canvas projection (absent when the IR is empty or invalid).
  final CanvasProjection? canvas;

  factory CanonicalEditorDocument.fromJson(Map<String, dynamic> json) {
    return CanonicalEditorDocument(
      irJson: Map<String, dynamic>.from(
        json['ir_json'] as Map? ?? const <String, dynamic>{},
      ),
      cnlText: _sanitizeLegacyTensorValueClauses(
        json['cnl_text'] as String? ?? '',
      ),
      fidelityAnnotations:
          (json['fidelity_annotations'] as List<dynamic>? ?? const [])
              .map(
                (e) => FidelityAnnotation.fromJson(e as Map<String, dynamic>),
              )
              .toList(),
      canvas: json['canvas'] != null
          ? CanvasProjection.fromJson(json['canvas'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'ir_json': irJson,
    'cnl_text': cnlText,
    'fidelity_annotations': fidelityAnnotations.map((a) => a.toJson()).toList(),
    if (canvas != null) 'canvas': canvas!.toJson(),
  };
}

/// Response from `POST /api/neurosim/parse-cnl-canonical`.
class ParseCnlResponse {
  const ParseCnlResponse({required this.document, this.diagnostics = const []});

  final CanonicalEditorDocument document;

  /// Diagnostic messages produced during parsing (non-fatal warnings).
  final List<String> diagnostics;

  factory ParseCnlResponse.fromJson(Map<String, dynamic> json) {
    return ParseCnlResponse(
      document: CanonicalEditorDocument.fromJson(
        json['document'] as Map<String, dynamic>,
      ),
      diagnostics: (json['diagnostics'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'document': document.toJson(),
    'diagnostics': diagnostics,
  };
}

/// Response from `POST /api/neurosim/generate-cnl-canonical`.
class GenerateCnlCanonicalResponse {
  const GenerateCnlCanonicalResponse({
    required this.cnlText,
    required this.document,
  });

  final String cnlText;
  final CanonicalEditorDocument document;

  factory GenerateCnlCanonicalResponse.fromJson(Map<String, dynamic> json) {
    return GenerateCnlCanonicalResponse(
      cnlText: _sanitizeLegacyTensorValueClauses(json['cnl_text'] as String),
      document: CanonicalEditorDocument.fromJson(
        json['document'] as Map<String, dynamic>,
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'cnl_text': cnlText,
    'document': document.toJson(),
  };
}
