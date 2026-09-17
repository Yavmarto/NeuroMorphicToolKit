import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:neuro_toolkit/features/neurocnl/models/flash_job_status.dart';

/// HTTP client for the Neurochip backend API.
///
/// Handles firmware generation, serial port discovery, and flash job
/// management through the root-selected suite backend.
class NeurochipClient {
  final String baseUrl;
  final String apiKey;
  final http.Client _http;

  NeurochipClient({
    required String baseUrl,
    this.apiKey = '',
    http.Client? httpClient,
  }) : baseUrl = _resolveBaseUrl(baseUrl),
       _http = httpClient ?? http.Client();

  static String _resolveBaseUrl(String rawBaseUrl) {
    final parsed = Uri.parse(rawBaseUrl);
    return parsed
        .replace(path: '', queryParameters: null, fragment: null)
        .toString();
  }

  // ── Serial ports ──────────────────────────────────────────────────────────

  /// Returns the list of serial port objects from the Neurochip backend.
  ///
  /// Each map contains at least:
  ///   - `port` (String) — OS device path, e.g. `/dev/cu.usbmodem1`
  ///   - `description` (String)
  ///   - `is_teensy` (bool) — true when the USB VID matches Teensy
  Future<List<Map<String, dynamic>>> getSerialPorts() async {
    final response = await _getJson('/api/neurochip/serial/ports');
    final List<dynamic> raw;
    if (response is List) {
      raw = response;
    } else if (response is Map<String, dynamic>) {
      raw = (response['ports'] as List?) ?? [];
    } else {
      throw NeurochipApiException(
        500,
        'Unexpected serial ports payload: ${response.runtimeType}',
      );
    }
    return raw.map((p) => Map<String, dynamic>.from(p as Map)).toList();
  }

  // ── Firmware export ───────────────────────────────────────────────────────

  /// Calls `POST /api/neurochip/export/teensy` with [networkPayload] (a
  /// Neurochip `NetworkInput`-compatible JSON dict) and returns the raw ZIP
  /// bytes of the generated firmware archive.
  Future<Uint8List> exportTeensyFirmware(
    Map<String, dynamic> networkPayload,
  ) async {
    final uri = Uri.parse('$baseUrl/api/neurochip/export/teensy');
    final headers = {'Content-Type': 'application/json'};
    if (apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }

    final response = await _http.post(
      uri,
      headers: headers,
      body: jsonEncode(networkPayload),
    );

    if (response.statusCode != 200) {
      throw NeurochipApiException(response.statusCode, response.body);
    }

    return response.bodyBytes;
  }

  // ── Flash ─────────────────────────────────────────────────────────────────

  /// Uploads a firmware ZIP [zipBytes] and requests flashing to [port].
  ///
  /// Returns the `job_id` string used to poll [getFlashStatus].
  Future<String> startFlash(Uint8List zipBytes, String port) async {
    final uri = Uri.parse('$baseUrl/api/neurochip/serial/flash');
    final request = http.MultipartRequest('POST', uri);
    if (apiKey.isNotEmpty) {
      request.headers['X-API-Key'] = apiKey;
    }

    request.files.add(
      http.MultipartFile.fromBytes('file', zipBytes, filename: 'firmware.zip'),
    );
    request.fields['port'] = port;

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw NeurochipApiException(streamed.statusCode, body);
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final jobId = decoded['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      throw NeurochipApiException(500, 'Flash response missing job_id: $body');
    }
    return jobId;
  }

  /// Polls `GET /api/neurochip/serial/flash/{jobId}` once and returns the
  /// current [FlashJobStatus].
  Future<FlashJobStatus> getFlashStatus(String jobId) async {
    final response = await _getJson('/api/neurochip/serial/flash/$jobId');
    if (response is! Map<String, dynamic>) {
      throw NeurochipApiException(
        500,
        'Unexpected flash status payload: ${response.runtimeType}',
      );
    }
    return FlashJobStatus.fromJson(response);
  }

  // ── Lava simulator ───────────────────────────────────────────────────────

  Future<String> compileLavaNetwork(
    Map<String, dynamic> networkPayload, {
    String runConfig = 'sim',
  }) async {
    final response = await _postJson(
      '/api/neurochip/hardware/lava/compile',
      <String, dynamic>{'network': networkPayload, 'run_config': runConfig},
    );
    if (response is! Map<String, dynamic>) {
      throw NeurochipApiException(
        500,
        'Unexpected Lava compile payload: ${response.runtimeType}',
      );
    }
    final sessionId = response['session_id'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      throw const NeurochipApiException(
        500,
        'Lava compile response missing session_id.',
      );
    }
    return sessionId;
  }

  Future<Map<String, dynamic>> runLavaSession(
    String sessionId, {
    int steps = 100,
  }) async {
    final response = await _postJson(
      '/api/neurochip/hardware/lava/run',
      <String, dynamic>{'session_id': sessionId, 'steps': steps},
    );
    if (response is! Map<String, dynamic>) {
      throw NeurochipApiException(
        500,
        'Unexpected Lava run payload: ${response.runtimeType}',
      );
    }
    return response;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<dynamic> _postJson(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {'Content-Type': 'application/json'};
    if (apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }

    final response = await _http.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw NeurochipApiException(response.statusCode, response.body);
    }
    return jsonDecode(response.body);
  }

  Future<dynamic> _getJson(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{};
    if (apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }

    final response = await _http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      throw NeurochipApiException(response.statusCode, response.body);
    }
    return jsonDecode(response.body);
  }

  void dispose() => _http.close();
}

/// Exception thrown when a Neurochip API request fails.
class NeurochipApiException implements Exception {
  final int statusCode;
  final String body;

  const NeurochipApiException(this.statusCode, this.body);

  @override
  String toString() => 'NeurochipApiException($statusCode): $body';
}
