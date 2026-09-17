/// HTTP client for the simulator contract endpoints.
///
/// Wraps:
///   GET  /api/simulators/capabilities
///   POST /api/simulators/run
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:neuro_toolkit/features/neurocnl/models/simulator.dart';

/// Raised when an API call returns a non-200 HTTP status.
class SimulatorApiException implements Exception {
  final int statusCode;
  final String body;

  const SimulatorApiException(this.statusCode, this.body);

  @override
  String toString() => 'SimulatorApiException($statusCode): $body';

  /// Returns the structured error string from the detail payload when available.
  String get userMessage {
    final messages = detailMessages;
    if (messages.isNotEmpty) {
      return messages.first;
    }
    return 'Simulator request failed ($statusCode).';
  }

  /// Returns every structured error/hint/example string the backend supplied.
  List<String> get detailMessages {
    final details = <String>[];
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final detail = decoded['detail'];
      if (detail is Map) {
        final messages = detail['messages'];
        if (messages is List) {
          details.addAll(messages.map((e) => e.toString()));
        }
        final items = detail['items'];
        if (items is List) {
          for (final item in items) {
            if (item is! Map) continue;
            final code = item['code']?.toString();
            final message = item['message']?.toString();
            final hint = item['hint']?.toString();
            if (message != null && message.isNotEmpty) {
              details.add(
                code == null || code.isEmpty ? message : '$code: $message',
              );
            }
            if (hint != null && hint.isNotEmpty) {
              details.add('Hint: $hint');
            }
          }
        }
        final hint = detail['hint'];
        if (hint is String && hint.isNotEmpty) {
          details.add('Hint: $hint');
        }
        final examples = detail['examples'];
        if (examples is List && examples.isNotEmpty) {
          details.addAll(examples.map((e) => 'Example: $e'));
        }
      }
    } catch (_) {}
    return details.toSet().toList();
  }
}

class SimulatorService {
  final String baseUrl;
  final String apiKey;
  final http.Client _http;

  SimulatorService({
    required String baseUrl,
    this.apiKey = '',
    http.Client? httpClient,
  }) : baseUrl = _normalizeBaseUrl(baseUrl),
       _http = httpClient ?? http.Client();

  static String _normalizeBaseUrl(String url) {
    var trimmed = url.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  Uri _buildUri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalizedPath');
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (apiKey.isNotEmpty) 'X-API-Key': apiKey,
  };

  /// Fetch capability profiles for all simulator backends.
  Future<List<SimulatorCapability>> getCapabilities() async {
    final uri = _buildUri('/simulators/capabilities');
    final response = await _http.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw SimulatorApiException(response.statusCode, response.body);
    }
    final list = jsonDecode(response.body) as List;
    return list
        .map((e) => SimulatorCapability.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Compile [request.spec] to NIR and run it in the requested simulator backend.
  Future<SimulatorRunResult> run(SimulatorRunRequest request) async {
    final uri = _buildUri('/simulators/run');
    final response = await _http.post(
      uri,
      headers: _headers,
      body: jsonEncode(request.toJson()),
    );
    if (response.statusCode == 200) {
      return SimulatorRunResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw SimulatorApiException(response.statusCode, response.body);
  }
}
