// ponytail: shared base eliminates ~200 lines of HTTP duplication between
// api_client.dart and canvas_api_client.dart.
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Shared HTTP infrastructure for all neurocnl service clients.
///
/// Provides:
///   - [baseUrl] / [_httpClient] fields
///   - [dispose] lifecycle method
///   - [decodeBody] / [decodeBodyAsMap] / [decodeBodyAsList] helpers
///   - [buildUri] URI builder with optional query parameters
///   - [basePost] / [baseGet] JSON-over-HTTP helpers with optional API key
///     and a pluggable error factory.
abstract class BaseHttpClient {
  BaseHttpClient({
    required this.baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  }) : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final http.Client _httpClient;

  // ── URI construction ───────────────────────────────────────────

  /// Builds a [Uri] for [path] relative to [baseUrl], merging any
  /// [queryParameters] onto the resolved URI.
  Uri buildUri(String path, {Map<String, String>? queryParameters}) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final uri = Uri.parse('$baseUrl/$normalizedPath');
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }
    return uri.replace(
      queryParameters: {...uri.queryParameters, ...queryParameters},
    );
  }

  // ── JSON body helpers ──────────────────────────────────────────

  dynamic decodeBody(http.Response response) => jsonDecode(response.body);

  Map<String, dynamic> decodeBodyAsMap(http.Response response) {
    final decoded = decodeBody(response);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Expected JSON object response: ${response.body}');
    }
    return decoded;
  }

  List<dynamic> decodeBodyAsList(http.Response response) {
    final decoded = decodeBody(response);
    if (decoded is! List<dynamic>) {
      throw Exception('Expected JSON list response: ${response.body}');
    }
    return decoded;
  }

  // ── JSON GET / POST with optional API key ──────────────────────

  /// Performs a GET request to [path] and returns the decoded JSON map.
  ///
  /// [apiKey] is added as `X-API-Key` when non-empty.
  /// [errorFactory] is called on non-200 responses; defaults to throwing an
  /// [ApiRequestException]. Subclasses that use a different error type should
  /// pass their own factory.
  Future<Map<String, dynamic>> baseGet(
    String path, {
    String apiKey = '',
    Exception Function(int statusCode, String body)? errorFactory,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{};
    if (apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }
    final response = await _httpClient
        .get(uri, headers: headers)
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw (errorFactory ?? _defaultError)(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Performs a POST request to [path] with a JSON [body] and returns the
  /// decoded JSON map.
  ///
  /// [apiKey] is added as `X-API-Key` when non-empty.
  Future<Map<String, dynamic>> basePost(
    String path,
    Map<String, dynamic> body, {
    String apiKey = '',
    Exception Function(int statusCode, String body)? errorFactory,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }
    final response = await _httpClient
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw (errorFactory ?? _defaultError)(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ── Raw client access for subclasses ──────────────────────────

  /// Exposes the underlying [http.Client] for subclass use cases that cannot
  /// be expressed through [baseGet] / [basePost] (e.g. multipart, SSE, binary
  /// responses). Prefer the typed helpers for standard JSON calls.
  http.Client get rawHttpClient => _httpClient;

  // ── Lifecycle ──────────────────────────────────────────────────

  void dispose() => _httpClient.close();
}

// ── Default error type ─────────────────────────────────────────

Exception _defaultError(int statusCode, String body) =>
    ApiRequestException(statusCode, body);

/// Thrown by [BaseHttpClient.baseGet] / [BaseHttpClient.basePost] when the
/// server returns a non-200 status code and no custom error factory is
/// provided.  [ApiClient] in api_client.dart re-uses [ApiException] (a
/// subtype) instead.
class ApiRequestException implements Exception {
  const ApiRequestException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiRequestException($statusCode): $body';
}
