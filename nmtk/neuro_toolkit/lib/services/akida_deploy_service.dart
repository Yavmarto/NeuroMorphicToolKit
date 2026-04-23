import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:path/path.dart' as p;

/// REST client for Akida deployment endpoints.
///
/// Talks to:
/// - NeuroCNL (port 8000): /api/deploy/akida/network
/// - Neurochip (port 8002): /api/neurochip/akida/{deploy,status,verify}
/// - Neurobench (port 8003): /api/neurobench/run
class AkidaDeployService {
  AkidaDeployService({
    http.Client? httpClient,
    String? neurocnlBaseUrl,
    String? neurochipBaseUrl,
    String? neurobenchBaseUrl,
    String? controlApiBaseUrl,
  }) : _httpClient = httpClient ?? http.Client(),
       _neurocnlBaseUrl = neurocnlBaseUrl ?? 'http://localhost:8000',
       _neurochipBaseUrl = resolveNeurochipBaseUrl(
         explicitBaseUrl: neurochipBaseUrl,
         controlApiBaseUrl: controlApiBaseUrl,
       ),
       _neurobenchBaseUrl = neurobenchBaseUrl ?? 'http://localhost:8003';

  final http.Client _httpClient;
  final String _neurocnlBaseUrl;
  final String _neurochipBaseUrl;
  final String _neurobenchBaseUrl;

  static String resolveNeurochipBaseUrl({
    String? explicitBaseUrl,
    String? controlApiBaseUrl,
  }) {
    final normalizedExplicit = _normalizeBaseUrl(explicitBaseUrl);
    if (normalizedExplicit != null) {
      return normalizedExplicit;
    }

    final normalizedConfigured = _normalizeBaseUrl(
      const String.fromEnvironment('NMTK_NEUROCHIP_BASE_URL', defaultValue: ''),
    );
    if (normalizedConfigured != null) {
      return normalizedConfigured;
    }

    final normalizedControl = _normalizeBaseUrl(
      controlApiBaseUrl ??
          const String.fromEnvironment(
            'NMTK_CONTROL_API_BASE_URL',
            defaultValue: '',
          ),
    );
    if (normalizedControl != null) {
      final controlUri = Uri.parse(normalizedControl);
      final scheme = controlUri.scheme.trim().isEmpty
          ? 'http'
          : controlUri.scheme;
      final host = controlUri.host.trim().isEmpty
          ? 'localhost'
          : controlUri.host;
      return Uri(scheme: scheme, host: host, port: 8002).toString();
    }

    return 'http://localhost:8002';
  }

  static String? _normalizeBaseUrl(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  /// Check Akida exportability for a CNL spec.
  ///
  /// Calls POST /api/deploy/akida/network on the NeuroCNL backend.
  /// Returns exportability only; runtime SDK proof is a later Neurochip step.
  /// Throws [AkidaDeployException] on HTTP or parse errors.
  Future<AkidaNetworkResponse> checkExportability({
    required String spec,
    required int weightBitWidth,
    String akidaVersion = 'akida1',
  }) async {
    final uri = Uri.parse('$_neurocnlBaseUrl/api/deploy/akida/network');
    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'spec': spec,
        'weight_bit_width': weightBitWidth,
        'akida_version': akidaVersion,
      }),
    );

    if (response.statusCode == 200) {
      return AkidaNetworkResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }

    final detail = _parseErrorDetail(response.body);
    throw AkidaDeployException(
      error: detail['error'] as String? ?? 'HTTP ${response.statusCode}',
      messages: _extractMessages(detail),
    );
  }

  /// Download the Akida scaffold package as a ZIP file.
  ///
  /// Calls POST /api/neurochip/akida/deploy/mapped with the pre-mapped network
  /// returned by the NeuroCNL exportability check. Saves the bytes to
  /// [outputDir]/akida_deploy.zip. Returns the absolute path of the saved file.
  /// Throws [AkidaDeployException] on failure.
  Future<String> downloadPackage({
    required Map<String, dynamic> mappedNetwork,
    required int bitWidth,
    required String outputDir,
  }) async {
    final uri = Uri.parse(
      '$_neurochipBaseUrl/api/neurochip/akida/deploy/mapped?bit_width=$bitWidth',
    );
    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(mappedNetwork),
    );

    if (response.statusCode == 200) {
      final outPath = p.join(outputDir, 'akida_deploy.zip');
      await File(outPath).writeAsBytes(response.bodyBytes);
      return outPath;
    }

    final detail = _parseErrorDetail(response.body);
    throw AkidaDeployException(
      error: detail['error'] as String? ?? 'deploy_failed',
      messages: _extractMessages(detail),
    );
  }

  /// Query the current Akida backend state from Neurochip.
  ///
  /// Calls GET /api/neurochip/akida/status.
  /// Returns [AkidaDeployJob] on success.
  Future<AkidaDeployJob> getStatus() async {
    final uri = Uri.parse('$_neurochipBaseUrl/api/neurochip/akida/status');
    final response = await _httpClient.get(uri);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return AkidaDeployJob.fromJson(json);
    }

    throw AkidaDeployException(
      error: 'status_check_failed',
      messages: ['HTTP ${response.statusCode}'],
    );
  }

  /// Verify that the mapped network is deployable in the current Neurochip runtime.
  ///
  /// Calls POST /api/neurochip/akida/verify. When [mappedNetwork] is supplied
  /// the backend verifies a fresh construction of that payload rather than any
  /// previously cached runtime state.
  Future<AkidaSdkVerification> verifySdk({
    Map<String, dynamic>? mappedNetwork,
    int bitWidth = 4,
  }) async {
    final uri = Uri.parse(
      '$_neurochipBaseUrl/api/neurochip/akida/verify?bit_width=$bitWidth',
    );
    final response = await _httpClient.post(
      uri,
      headers: mappedNetwork == null
          ? null
          : {'Content-Type': 'application/json'},
      body: mappedNetwork == null ? null : jsonEncode(mappedNetwork),
    );

    if (response.statusCode == 200) {
      return AkidaSdkVerification.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }

    final detail = _parseErrorDetail(response.body);
    throw AkidaDeployException(
      error: detail['error'] as String? ?? 'sdk_verify_failed',
      messages: _extractMessages(detail),
    );
  }

  /// Submit a Neurobench benchmark job for the deployed Akida model.
  ///
  /// Calls POST /api/neurobench/run.
  /// Returns the job ID on success.
  Future<String> runNeurobenchJob({
    required String benchmarkId,
    required String networkPath,
    String target = 'simulation',
  }) async {
    final uri = Uri.parse('$_neurobenchBaseUrl/api/neurobench/run');
    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'benchmark_id': benchmarkId,
        'network_path': networkPath,
        'target': target,
      }),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json['job_id'] as String;
    }

    final detail = _parseErrorDetail(response.body);
    throw AkidaDeployException(
      error: detail['error'] as String? ?? 'neurobench_submit_failed',
      messages: _extractMessages(detail),
    );
  }

  /// Poll the status of a Neurobench benchmark job.
  ///
  /// Calls GET /api/neurobench/run/{jobId}.
  Future<Map<String, dynamic>> getNeurobenchJobStatus(String jobId) async {
    final uri = Uri.parse('$_neurobenchBaseUrl/api/neurobench/run/$jobId');
    final response = await _httpClient.get(uri);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw AkidaDeployException(
      error: 'neurobench_poll_failed',
      messages: ['HTTP ${response.statusCode}'],
    );
  }

  void dispose() {
    _httpClient.close();
  }

  Map<String, dynamic> _parseErrorDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is Map<String, dynamic>) return detail;
        return {'error': detail?.toString() ?? body};
      }
    } catch (_) {}
    return {'error': body};
  }

  List<String> _extractMessages(Map<String, dynamic> detail) {
    final msgs = detail['messages'];
    if (msgs is List) return msgs.map((e) => e.toString()).toList();
    return [];
  }
}

class AkidaDeployException implements Exception {
  final String error;
  final List<String> messages;

  const AkidaDeployException({required this.error, this.messages = const []});

  @override
  String toString() {
    final parts = <String>[error, ...messages];
    return 'AkidaDeployException: ${parts.join(" — ")}';
  }
}
