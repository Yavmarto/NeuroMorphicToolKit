import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// REST client for PYNQ Z2 deployment endpoints.
///
/// Talks to:
/// - NeuroCNL (port 8000): /api/deploy/pynq/network
/// - Neurochip PYNQ board (user-configured): /hardware/pynq/{deploy,status,verify}
class PynqDeployService {
  PynqDeployService({
    http.Client? httpClient,
    String? neurocnlBaseUrl,
  })  : _httpClient = httpClient ?? http.Client(),
        _neurocnlBaseUrl = neurocnlBaseUrl ?? 'http://localhost:8000';

  final http.Client _httpClient;
  final String _neurocnlBaseUrl;

  /// Check PYNQ exportability for a CNL spec.
  ///
  /// Calls POST /api/deploy/pynq/network on the NeuroCNL backend.
  /// Returns [PynqNetworkResponse] on success.
  /// Throws [PynqDeployException] on parse/lower/HTTP errors.
  Future<PynqNetworkResponse> checkExportability({
    required String spec,
    required int weightBitWidth,
  }) async {
    final uri = Uri.parse('$_neurocnlBaseUrl/api/deploy/pynq/network');
    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'spec': spec,
        'weight_bit_width': weightBitWidth,
      }),
    );

    if (response.statusCode == 200) {
      return PynqNetworkResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }

    final detail = jsonDecode(response.body);
    if (detail is Map<String, dynamic> && detail.containsKey('detail')) {
      final d = detail['detail'];
      if (d is Map<String, dynamic>) {
        throw PynqDeployException(
          error: d['error'] as String? ?? 'unknown',
          messages: (d['messages'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [],
        );
      }
      throw PynqDeployException(error: d.toString());
    }
    throw PynqDeployException(
      error: 'HTTP ${response.statusCode}',
      messages: [response.body],
    );
  }

  /// Deploy overlay to a remote PYNQ Z2 board.
  ///
  /// Calls POST {boardBaseUrl}/hardware/pynq/deploy.
  /// Returns the raw JSON response dict on success.
  /// Throws [PynqDeployException] on failure.
  Future<Map<String, dynamic>> deployToBoard({
    required String boardBaseUrl,
    required List<double> weights,
    required Map<String, dynamic> config,
    String? bitstreamPath,
    Map<String, dynamic>? registerMap,
    String? apiKey,
  }) async {
    final uri = Uri.parse(
      '${boardBaseUrl.replaceAll(RegExp(r'/$'), '')}/hardware/pynq/deploy',
    );
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }

    final body = <String, dynamic>{
      'weights': weights,
      'config': config,
    };
    if (bitstreamPath != null && bitstreamPath.isNotEmpty) {
      body['bitstream_path'] = bitstreamPath;
    }
    if (registerMap != null && registerMap.isNotEmpty) {
      body['register_map'] = registerMap;
    }

    final response = await _httpClient.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw PynqDeployException(
      error: 'Deploy failed',
      messages: ['HTTP ${response.statusCode}: ${response.body}'],
    );
  }

  /// Poll the deployment status of a remote PYNQ Z2 board.
  ///
  /// Calls GET {boardBaseUrl}/hardware/pynq/status.
  /// Returns [PynqDeployJob] on success.
  Future<PynqDeployJob> getDeployStatus({
    required String boardBaseUrl,
    String? apiKey,
  }) async {
    final uri = Uri.parse(
      '${boardBaseUrl.replaceAll(RegExp(r'/$'), '')}/hardware/pynq/status',
    );
    final headers = <String, String>{};
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }

    final response = await _httpClient.get(uri, headers: headers);

    if (response.statusCode == 200) {
      return PynqDeployJob.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw PynqDeployException(
      error: 'Status check failed',
      messages: ['HTTP ${response.statusCode}'],
    );
  }

  /// Run SITL verification on the remote PYNQ Z2 board.
  ///
  /// Calls POST {boardBaseUrl}/hardware/pynq/verify.
  /// Returns [PynqSitlVerifyResult] on success.
  Future<PynqSitlVerifyResult> runSitlVerification({
    required String boardBaseUrl,
    String? apiKey,
    List<double>? weights,
    Map<String, dynamic>? config,
  }) async {
    final uri = Uri.parse(
      '${boardBaseUrl.replaceAll(RegExp(r'/$'), '')}/hardware/pynq/verify',
    );
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }

    final body = <String, dynamic>{};
    if (weights != null) body['weights'] = weights;
    if (config != null) body['config'] = config;

    final response = await _httpClient.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return PynqSitlVerifyResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    if (response.statusCode == 400) {
      throw PynqDeployException(
        error: 'No backend deployed — call deploy first',
      );
    }
    throw PynqDeployException(
      error: 'SITL verification failed',
      messages: ['HTTP ${response.statusCode}: ${response.body}'],
    );
  }

  void dispose() {
    _httpClient.close();
  }
}

class PynqDeployException implements Exception {
  final String error;
  final List<String> messages;

  PynqDeployException({
    required this.error,
    this.messages = const [],
  });

  @override
  String toString() {
    final parts = <String>[error, ...messages];
    return 'PynqDeployException: ${parts.join(" — ")}';
  }
}
