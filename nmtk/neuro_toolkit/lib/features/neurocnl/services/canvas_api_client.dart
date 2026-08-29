import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:neuro_toolkit/features/neurocnl/services/base_http_client.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/component.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/preview.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/project.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/sweep.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart';
import 'package:neuro_toolkit/features/neurocnl/models/custom_node_source.dart';

class CanvasSyncException implements Exception {
  CanvasSyncException({
    required this.message,
    this.statusCode,
    this.unsupportedConcepts = const [],
  });

  final String message;
  final int? statusCode;
  final List<String> unsupportedConcepts;

  @override
  String toString() => message;
}

/// Response from `POST /api/neurosim/nir/import`.
///
/// [importId] is an opaque handle to the real weight values in the uploaded
/// `.nir` file (the CNL text derived from [graph] only carries shapes, not
/// real tensor values, by design). It should be forwarded to
/// `generate-notebook-v2` so the generated notebook can recover the real
/// trained weights instead of shipping placeholder/untrained ones.
class ImportNirBytesResponse {
  const ImportNirBytesResponse({required this.graph, this.importId = ''});

  final CanvasGraph graph;
  final String importId;
}

class ApiClient extends BaseHttpClient {
  ApiClient({required String baseUrl, super.httpClient})
    : super(baseUrl: _normalizeBaseUrl(baseUrl));

  static const String _apiPrefix = '/api/neurosim';
  // Canvas requests always use the root-selected backend origin.
  static const String _studioApiPrefix = '/api/neurocnl';

  static String _normalizeBaseUrl(String rawBaseUrl) {
    final normalizedInput = rawBaseUrl.trim();
    final parsed = Uri.tryParse(normalizedInput);
    if (parsed == null) {
      final trimmed = normalizedInput.endsWith('/')
          ? normalizedInput.substring(0, normalizedInput.length - 1)
          : normalizedInput;
      if (trimmed.endsWith(_apiPrefix)) {
        return trimmed;
      }
      if (trimmed.endsWith(_studioApiPrefix)) {
        return '${trimmed.substring(0, trimmed.length - _studioApiPrefix.length)}$_apiPrefix';
      }
      return '$trimmed$_apiPrefix';
    }

    final normalizedPath = parsed.path.endsWith('/')
        ? parsed.path.substring(0, parsed.path.length - 1)
        : parsed.path;
    final nextPath = switch (normalizedPath) {
      _apiPrefix => _apiPrefix,
      _studioApiPrefix => _apiPrefix,
      '' || '/' => _apiPrefix,
      _ => '$normalizedPath$_apiPrefix',
    };
    return parsed
        .replace(path: nextPath, queryParameters: null, fragment: null)
        .toString();
  }

  CanvasSyncException _buildCanvasSyncException(
    String fallbackMessage,
    http.Response response,
  ) {
    final responseBody = response.body.trim();
    if (responseBody.isEmpty) {
      return CanvasSyncException(
        message: fallbackMessage,
        statusCode: response.statusCode,
      );
    }

    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String) {
          return CanvasSyncException(
            message: detail,
            statusCode: response.statusCode,
          );
        }
        if (detail is Map<String, dynamic>) {
          return CanvasSyncException(
            message: detail['message']?.toString() ?? fallbackMessage,
            statusCode: response.statusCode,
            unsupportedConcepts:
                (detail['unsupported_concepts'] as List? ?? const [])
                    .map((item) => item.toString())
                    .toList(),
          );
        }
      }
    } catch (_) {
      // Fall through to a raw response-body message.
    }

    return CanvasSyncException(
      message: '$fallbackMessage: $responseBody',
      statusCode: response.statusCode,
    );
  }

  Future<List<String>> fetchCategories() async {
    final response = await rawHttpClient.get(
      buildUri('components/categories'),
      headers: const {},
    );
    if (response.statusCode == 200) {
      final data = decodeBodyAsList(response);
      return data.cast<String>();
    } else {
      throw Exception('Failed to fetch categories: ${response.body}');
    }
  }

  Future<List<ComponentBlock>> fetchComponents({String? category}) async {
    final response = await rawHttpClient.get(
      buildUri(
        'components',
        queryParameters: category == null ? null : {'category': category},
      ),
      headers: const {},
    );
    if (response.statusCode == 200) {
      final data = decodeBodyAsList(response);
      return data
          .map((json) => ComponentBlock.fromJson(json as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('Failed to fetch components: ${response.body}');
    }
  }

  Future<CustomNodeSource> fetchCustomNodeSource({
    required String componentId,
    required String displayName,
    required String category,
    required Map<String, dynamic> parameters,
    String? nirType,
    String? pipelineType,
    String? canvasContext,
    List<Map<String, dynamic>> parameterDefinitions = const [],
    List<Map<String, dynamic>> ports = const [],
  }) async {
    final response = await rawHttpClient.post(
      buildUri('custom-nodes/source'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'component_id': componentId,
        'nir_type': nirType,
        'pipeline_type': pipelineType,
        'canvas_context': canvasContext,
        'display_name': displayName,
        'category': category,
        'parameters': parameters,
        'parameter_definitions': parameterDefinitions,
        'ports': ports,
      }),
    );
    if (response.statusCode != 200) {
      throw _buildCanvasSyncException(
        'The Python source could not be opened',
        response,
      );
    }
    return CustomNodeSource.fromJson(decodeBodyAsMap(response));
  }

  Future<CustomNodeValidation> validateCustomNodeSource(String source) async {
    final response = await rawHttpClient.post(
      buildUri('custom-nodes/validate'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{'source': source}),
    );
    if (response.statusCode != 200) {
      throw _buildCanvasSyncException(
        'Python validation is temporarily unavailable',
        response,
      );
    }
    return CustomNodeValidation.fromJson(decodeBodyAsMap(response));
  }

  Future<CustomNodeSaveResult> saveCustomNodeSource({
    required String source,
    required bool saveAs,
    String? targetComponentId,
    String? expectedRevision,
  }) async {
    final response = await rawHttpClient.post(
      buildUri('custom-nodes/save'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'source': source,
        'save_as': saveAs,
        'target_component_id': ?targetComponentId,
        'expected_revision': ?expectedRevision,
      }),
    );
    if (response.statusCode != 200) {
      throw _buildCanvasSyncException(
        response.statusCode == 409
            ? 'This custom node changed elsewhere; reload it before saving'
            : 'The custom node could not be saved',
        response,
      );
    }
    return CustomNodeSaveResult.fromJson(decodeBodyAsMap(response));
  }

  Future<PreviewResponse> runPreview(CanvasGraph graph) async {
    final request = PreviewRequest(graph: graph);
    final response = await rawHttpClient.post(
      buildUri('preview'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    if (response.statusCode == 200) {
      return PreviewResponse.fromJson(decodeBodyAsMap(response));
    } else {
      throw Exception('Failed to run preview: ${response.body}');
    }
  }

  Future<PreviewResponse> getSimulationStatus(String jobId) async {
    final response = await rawHttpClient.get(
      buildUri('simulations/$jobId'),
      headers: const {},
    );
    if (response.statusCode == 200) {
      return PreviewResponse.fromJson(decodeBodyAsMap(response));
    } else {
      throw Exception('Failed to fetch simulation status: ${response.body}');
    }
  }

  Uri _previewWebSocketUri() {
    final httpUri = Uri.parse(baseUrl);
    final wsScheme = httpUri.scheme == 'https' ? 'wss' : 'ws';
    return httpUri.replace(
      scheme: wsScheme,
      path: '${httpUri.path}/ws/simulation',
    );
  }

  Stream<PreviewSocketMessage> streamPreview(CanvasGraph graph) async* {
    final channel = WebSocketChannel.connect(_previewWebSocketUri());
    try {
      channel.sink.add(jsonEncode(PreviewRequest(graph: graph).toJson()));
      await for (final message in channel.stream) {
        if (message is! String) {
          continue;
        }
        final decoded = jsonDecode(message);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        yield PreviewSocketMessage.fromJson(decoded);
      }
    } finally {
      await channel.sink.close();
    }
  }

  Future<Map<String, dynamic>> preflightExport(
    String format,
    Map<String, dynamic> graphJson,
  ) async {
    final response = await rawHttpClient.post(
      buildUri('export/$format', queryParameters: {'preflight': 'true'}),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(graphJson),
    );
    if (response.statusCode == 200) {
      return decodeBodyAsMap(response);
    } else {
      throw Exception('Failed to preflight export: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> exportGraph(
    String format,
    Map<String, dynamic> graphJson, {
    bool allowApproximate = false,
  }) async {
    final response = await rawHttpClient.post(
      buildUri(
        'export/$format',
        queryParameters: allowApproximate
            ? {'allow_approximate': 'true'}
            : null,
      ),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(graphJson),
    );
    if (response.statusCode == 200) {
      return decodeBodyAsMap(response);
    } else {
      throw Exception('Failed to export graph: ${response.body}');
    }
  }

  Future<String> generateCnl(CanvasGraph graph) async {
    final response = await rawHttpClient.post(
      buildUri('generate-cnl'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(graph.toJson()),
    );
    if (response.statusCode == 200) {
      final data = decodeBodyAsMap(response);
      final cnlSpec = data['cnl_spec'];
      if (cnlSpec is! String) {
        throw Exception('Expected cnl_spec string response: ${response.body}');
      }
      return cnlSpec;
    } else {
      throw _buildCanvasSyncException(
        'Failed to generate canonical CNL',
        response,
      );
    }
  }

  Future<CanvasGraph> parseCnl(String cnlSpec, {CanvasGraph? graph}) async {
    return repairCnl(cnlSpec, graph: graph);
  }

  /// Parse [specText] via the canonical endpoint and return a full
  /// [ParseCnlResponse] containing the IR-backed [CanonicalEditorDocument].
  Future<ParseCnlResponse> parseCnlCanonical(String specText) async {
    // See canvasToCanonical for why the timeout is required on these raw calls.
    final response = await rawHttpClient
        .post(
          buildUri('parse-cnl-canonical'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(<String, dynamic>{'spec_text': specText}),
        )
        .timeout(timeout);
    if (response.statusCode == 200) {
      return ParseCnlResponse.fromJson(decodeBodyAsMap(response));
    } else {
      throw _buildCanvasSyncException(
        'Failed to parse CNL (canonical)',
        response,
      );
    }
  }

  /// Generate CNL text from a [CanonicalEditorDocument] via the canonical
  /// endpoint and return the full [GenerateCnlCanonicalResponse].
  Future<GenerateCnlCanonicalResponse> generateCnlCanonical(
    CanonicalEditorDocument doc,
  ) async {
    final response = await rawHttpClient.post(
      buildUri('generate-cnl-canonical'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{'document': doc.toJson()}),
    );
    if (response.statusCode == 200) {
      return GenerateCnlCanonicalResponse.fromJson(decodeBodyAsMap(response));
    } else {
      throw _buildCanvasSyncException(
        'Failed to generate CNL (canonical)',
        response,
      );
    }
  }

  Future<ParseCnlResponse> canvasToCanonical(CanvasGraph graph) async {
    // .timeout is load-bearing here, not defensive polish: these raw calls
    // bypass basePost, which is where the shared timeout normally gets applied.
    // CanvasController._doPush decrements its in-flight counter from
    // whenComplete, so a request that never settles leaves the counter above
    // zero forever and permanently disables the canonical→canvas mirror.
    final response = await rawHttpClient
        .post(
          buildUri('canvas-to-canonical'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(<String, dynamic>{'graph': graph.toJson()}),
        )
        .timeout(timeout);
    if (response.statusCode == 200) {
      return ParseCnlResponse.fromJson(decodeBodyAsMap(response));
    }
    throw _buildCanvasSyncException(
      'Failed to derive canonical document from canvas',
      response,
    );
  }

  Future<ParseCnlResponse> applyCanvasMutation(
    CanonicalEditorDocument doc,
    Map<String, dynamic> mutation,
  ) async {
    final response = await rawHttpClient.post(
      buildUri('canvas-mutation'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'document': doc.toJson(),
        'mutation': mutation,
      }),
    );
    if (response.statusCode == 200) {
      return ParseCnlResponse.fromJson(decodeBodyAsMap(response));
    }
    throw _buildCanvasSyncException(
      'Failed to apply canvas mutation',
      response,
    );
  }

  Future<CanvasGraph> repairCnl(String cnlSpec, {CanvasGraph? graph}) async {
    final payload = <String, dynamic>{'cnl_spec': cnlSpec};
    payload['import_mode'] = 'repair';
    if (graph != null) {
      payload['graph'] = graph.toJson();
    }

    final response = await rawHttpClient.post(
      buildUri('parse-cnl'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (response.statusCode == 200) {
      return CanvasGraph.fromJson(decodeBodyAsMap(response));
    } else {
      throw _buildCanvasSyncException('Failed to parse CNL', response);
    }
  }

  Future<ValidationResult> validateGraph(CanvasGraph graph) async {
    final response = await rawHttpClient.post(
      buildUri('validate'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(graph.toJson()),
    );
    if (response.statusCode == 200) {
      return ValidationResult.fromJson(decodeBodyAsMap(response));
    } else {
      throw Exception('Failed to validate graph: ${response.body}');
    }
  }

  Future<ImportNirBytesResponse> importNirBytes(Uint8List payload) async {
    final response = await rawHttpClient.post(
      buildUri('nir/import'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{'content_b64': base64Encode(payload)}),
    );
    if (response.statusCode == 200) {
      final Map<String, dynamic> body = decodeBodyAsMap(response);
      return ImportNirBytesResponse(
        graph: CanvasGraph.fromJson(body['graph'] as Map<String, dynamic>),
        importId: body['import_id'] as String? ?? '',
      );
    }
    throw _buildCanvasSyncException('Failed to import NIR graph', response);
  }

  /// Translate raw .nir bytes directly into a canonical editor document.
  ///
  /// Calls `POST /api/neurosim/nir-to-canonical` which bypasses the CNL
  /// round-trip and therefore works for ALL NIR graphs, including those with
  /// node types outside the CNL-renderable subset (nir.Linear, nir.Conv2d,
  /// etc.).  Unsupported types appear as placeholder canvas nodes.
  Future<ParseCnlResponse> nirBytesToCanonical(Uint8List payload) async {
    // See canvasToCanonical for why the timeout is required on these raw calls.
    final response = await rawHttpClient
        .post(
          buildUri('nir-to-canonical'),
          headers: const {'Content-Type': 'application/octet-stream'},
          body: payload,
        )
        .timeout(timeout);
    if (response.statusCode == 200) {
      return ParseCnlResponse.fromJson(decodeBodyAsMap(response));
    }
    throw _buildCanvasSyncException(
      'Failed to derive canonical document from NIR bytes',
      response,
    );
  }

  /// Translate raw .nir bytes back to canonical CNL text.
  ///
  /// Sends the payload as a raw request body to
  /// `POST /api/neurosim/generate-cnl-from-nir` and returns the CNL string.
  Future<String> generateCnlFromNirBytes(Uint8List payload) async {
    final response = await rawHttpClient.post(
      buildUri('generate-cnl-from-nir'),
      headers: const {'Content-Type': 'application/octet-stream'},
      body: payload,
    );
    if (response.statusCode == 200) {
      final Map<String, dynamic> body = decodeBodyAsMap(response);
      return body['cnl_text'] as String;
    }
    throw _buildCanvasSyncException(
      'Failed to generate CNL from NIR',
      response,
    );
  }

  Future<Uint8List> exportNirBytes(CanvasGraph graph) async {
    final response = await rawHttpClient.post(
      buildUri('nir/export'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(graph.toJson()),
    );
    if (response.statusCode == 200) {
      final Map<String, dynamic> body = decodeBodyAsMap(response);
      final String content = body['content_b64'] as String;
      return base64Decode(content);
    }
    throw _buildCanvasSyncException('Failed to export NIR graph', response);
  }

  Future<List<ProjectSummary>> listProjects() async {
    final response = await rawHttpClient.get(
      buildUri('projects'),
      headers: const {},
    );
    if (response.statusCode == 200) {
      final data = decodeBodyAsList(response);
      return data
          .map((json) => ProjectSummary.fromJson(json as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('Failed to list projects: ${response.body}');
    }
  }

  Future<Project> createProject(CreateProjectRequest request) async {
    final response = await rawHttpClient.post(
      buildUri('projects'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    if (response.statusCode == 200) {
      return Project.fromJson(decodeBodyAsMap(response));
    } else {
      throw Exception('Failed to create project: ${response.body}');
    }
  }

  Future<Project> updateProject(
    String projectId,
    CreateProjectRequest request,
  ) async {
    final response = await rawHttpClient.put(
      buildUri('projects/$projectId'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    if (response.statusCode == 200) {
      return Project.fromJson(decodeBodyAsMap(response));
    } else {
      throw Exception('Failed to update project: ${response.body}');
    }
  }

  Future<void> deleteProject(String projectId) async {
    final response = await rawHttpClient.delete(
      buildUri('projects/$projectId'),
      headers: const {},
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Failed to delete project: ${response.body}');
    }
  }

  Future<Project> getProject(String projectId) async {
    final response = await rawHttpClient.get(
      buildUri('projects/$projectId'),
      headers: const {},
    );
    if (response.statusCode == 200) {
      return Project.fromJson(decodeBodyAsMap(response));
    } else {
      throw Exception('Failed to get project: ${response.body}');
    }
  }

  Future<SweepResponse> runSweep(SweepRequest request) async {
    final response = await rawHttpClient.post(
      buildUri('sweep'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    if (response.statusCode == 200) {
      return SweepResponse.fromJson(decodeBodyAsMap(response));
    } else {
      throw Exception('Failed to run sweep: ${response.body}');
    }
  }

  Future<SweepResponse> getSweepStatus(String jobId) async {
    final response = await rawHttpClient.get(
      buildUri('sweep/$jobId'),
      headers: const {},
    );
    if (response.statusCode == 200) {
      return SweepResponse.fromJson(decodeBodyAsMap(response));
    } else {
      throw Exception('Failed to fetch sweep status: ${response.body}');
    }
  }
}
