import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// REST client for Teensy deployment endpoints.
///
/// Talks to:
/// - NeuroCNL (port 8000): /api/deploy/teensy/network
/// - Neurochip (port 8002): /api/neurochip/export/teensy, serial routes
class TeensyDeployService {
  TeensyDeployService({
    http.Client? httpClient,
    String? neurocnlBaseUrl,
    String? neurochipBaseUrl,
  })  : _httpClient = httpClient ?? http.Client(),
        _neurocnlBaseUrl = neurocnlBaseUrl ?? 'http://localhost:8000',
        _neurochipBaseUrl = neurochipBaseUrl ?? 'http://localhost:8002';

  final http.Client _httpClient;
  final String _neurocnlBaseUrl;
  final String _neurochipBaseUrl;

  /// Parse, validate, and produce a Teensy deployment payload.
  ///
  /// Returns [TeensyNetworkResponse] on success (verdict + payload).
  /// Throws [TeensyDeployException] on rejection or parse errors.
  Future<TeensyNetworkResponse> deployNetwork({
    required String spec,
    required int weightBitWidth,
  }) async {
    final uri = Uri.parse('$_neurocnlBaseUrl/api/deploy/teensy/network');
    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'spec': spec,
        'weight_bit_width': weightBitWidth,
      }),
    );

    if (response.statusCode == 200) {
      return TeensyNetworkResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }

    final detail = jsonDecode(response.body);
    if (detail is Map<String, dynamic> && detail.containsKey('detail')) {
      final d = detail['detail'];
      if (d is Map<String, dynamic>) {
        throw TeensyDeployException(
          error: d['error'] as String? ?? 'unknown',
          messages:
              (d['messages'] as List?)?.map((e) => e.toString()).toList() ?? [],
          rejectionReasons: (d['rejection_reasons'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [],
        );
      }
      throw TeensyDeployException(error: d.toString());
    }
    throw TeensyDeployException(
      error: 'HTTP ${response.statusCode}',
      messages: [response.body],
    );
  }

  /// Generate Teensy firmware zip from a deployment payload.
  ///
  /// Returns the raw firmware zip bytes.
  Future<Uint8List> exportFirmware({
    required Map<String, dynamic> payload,
    int bitWidth = 8,
  }) async {
    final uri = Uri.parse('$_neurochipBaseUrl/api/neurochip/export/teensy')
        .replace(queryParameters: {'bit_width': bitWidth.toString()});
    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    throw TeensyDeployException(
      error: 'Firmware export failed',
      messages: ['HTTP ${response.statusCode}: ${response.body}'],
    );
  }

  /// List available serial ports.
  Future<List<SerialPortInfo>> listSerialPorts() async {
    final uri = Uri.parse('$_neurochipBaseUrl/api/neurochip/serial/ports');
    final response = await _httpClient.get(uri);

    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List;
      return list
          .map((e) => SerialPortInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw TeensyDeployException(
      error: 'Failed to list serial ports',
      messages: ['HTTP ${response.statusCode}'],
    );
  }

  /// Start a firmware flash job.
  ///
  /// Returns the initial [FlashJob] with the assigned job_id.
  Future<FlashJob> startFlash({
    required Uint8List firmwareZipBytes,
    required String serialPort,
  }) async {
    final uri = Uri.parse('$_neurochipBaseUrl/api/neurochip/serial/flash');
    final request = http.MultipartRequest('POST', uri)
      ..fields['port'] = serialPort
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        firmwareZipBytes,
        filename: 'firmware.zip',
      ));

    final streamedResponse = await _httpClient.send(request);
    final responseBody = await streamedResponse.stream.bytesToString();

    if (streamedResponse.statusCode == 200) {
      return FlashJob.fromJson(
        jsonDecode(responseBody) as Map<String, dynamic>,
      );
    }
    throw TeensyDeployException(
      error: 'Flash start failed',
      messages: ['HTTP ${streamedResponse.statusCode}: $responseBody'],
    );
  }

  /// Poll flash job status.
  Future<FlashJob> pollFlashJob(String jobId) async {
    final uri =
        Uri.parse('$_neurochipBaseUrl/api/neurochip/serial/flash/$jobId');
    final response = await _httpClient.get(uri);

    if (response.statusCode == 200) {
      return FlashJob.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    if (response.statusCode == 404) {
      throw TeensyDeployException(error: 'Flash job not found');
    }
    throw TeensyDeployException(
      error: 'Poll failed',
      messages: ['HTTP ${response.statusCode}'],
    );
  }

  /// Trigger post-flash runtime verification via Dream-Hand.
  Future<VerificationReport> verifyFlash({
    required String jobId,
    required String serialPort,
    bool runDemo = true,
    bool runHitl = false,
    int hitlSamples = 10,
    double timeoutS = 5.0,
  }) async {
    final uri = Uri.parse(
        '$_neurochipBaseUrl/api/neurochip/serial/flash/$jobId/verify');
    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'port': serialPort,
        'run_demo': runDemo,
        'run_hitl': runHitl,
        'hitl_samples': hitlSamples,
        'timeout_s': timeoutS,
      }),
    );

    if (response.statusCode == 200) {
      return VerificationReport.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    if (response.statusCode == 409) {
      throw TeensyDeployException(error: 'Flash job not yet complete');
    }
    if (response.statusCode == 503) {
      throw TeensyDeployException(
        error: 'neurodreamhand not installed on server',
      );
    }
    throw TeensyDeployException(
      error: 'Verification failed',
      messages: ['HTTP ${response.statusCode}: ${response.body}'],
    );
  }

  void dispose() {
    _httpClient.close();
  }
}

class TeensyDeployException implements Exception {
  final String error;
  final List<String> messages;
  final List<String> rejectionReasons;

  TeensyDeployException({
    required this.error,
    this.messages = const [],
    this.rejectionReasons = const [],
  });

  @override
  String toString() {
    final parts = <String>[error];
    if (messages.isNotEmpty) parts.addAll(messages);
    if (rejectionReasons.isNotEmpty) {
      parts.add('Rejection reasons: ${rejectionReasons.join(", ")}');
    }
    return 'TeensyDeployException: ${parts.join(" — ")}';
  }
}
