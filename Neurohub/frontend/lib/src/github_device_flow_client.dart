import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

/// Public configuration Neurohub hands out to start GitHub's OAuth Device Flow.
///
/// Maps to `GET /api/neurohub/oauth/config`. Only values that are safe to
/// share with a client are returned — no client secret, no redirect URI.
class GithubDeviceFlowConfig {
  const GithubDeviceFlowConfig({required this.clientId, required this.scopes});

  factory GithubDeviceFlowConfig.fromJson(Map<String, dynamic> json) {
    return GithubDeviceFlowConfig(
      clientId: json['client_id'] as String? ?? '',
      scopes: List<String>.from((json['scopes'] as List?) ?? const <dynamic>[]),
    );
  }

  final String clientId;
  final List<String> scopes;
}

/// Response to starting a device authorization request.
///
/// Maps to `POST /api/neurohub/oauth/device/start`. The server keeps the
/// `device_code` itself; the client only ever sees the user-facing values.
class GithubDeviceCodeStarted {
  const GithubDeviceCodeStarted({
    required this.sessionId,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  factory GithubDeviceCodeStarted.fromJson(Map<String, dynamic> json) {
    return GithubDeviceCodeStarted(
      sessionId: json['session_id'] as String,
      userCode: json['user_code'] as String,
      verificationUri: json['verification_uri'] as String,
      expiresIn: json['expires_in'] as int,
      interval: json['interval'] as int,
    );
  }

  final String sessionId;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;
}

/// One poll outcome for a pending device authorization session.
///
/// Maps to `POST /api/neurohub/oauth/device/poll`. [status] is one of
/// `pending`, `slow_down`, `expired`, `denied`, or `success`; [accessToken]
/// is only set on `success`.
class GithubDevicePollResult {
  const GithubDevicePollResult({
    required this.status,
    this.accessToken,
    this.interval,
  });

  factory GithubDevicePollResult.fromJson(Map<String, dynamic> json) {
    return GithubDevicePollResult(
      status: json['status'] as String,
      accessToken: json['access_token'] as String?,
      interval: json['interval'] as int?,
    );
  }

  final String status;
  final String? accessToken;
  final int? interval;

  bool get isSuccess => status == 'success';

  /// True once the flow can no longer progress and polling must stop.
  bool get isTerminal =>
      status == 'success' || status == 'expired' || status == 'denied';
}

/// HTTP client for Neurohub's GitHub OAuth Device Flow endpoints.
///
/// Talks only to the Neurohub backend (never directly to GitHub); Neurohub
/// mediates the whole exchange server-side. The base URL resolves through
/// [NmtkApiBaseUrl] so the same dart-define overrides the rest of the suite
/// uses apply. Inject an [http.Client] (e.g. `http/testing.dart`'s
/// `MockClient`) in tests.
class GithubDeviceFlowClient {
  GithubDeviceFlowClient({String? baseUrl, http.Client? httpClient})
    : baseUrl =
          baseUrl ??
          NmtkApiBaseUrl.resolve(apiPath: '/api/neurohub', defaultPort: 8005),
      _http = httpClient ?? http.Client();

  /// Resolved backend base URL, including the `/api/neurohub` prefix.
  final String baseUrl;
  final http.Client _http;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// Fetches the public Device Flow configuration (client id + scopes).
  Future<GithubDeviceFlowConfig> fetchConfig() async {
    final response = await _http.get(_uri('/oauth/config'));
    return _decode(
      response,
      GithubDeviceFlowConfig.fromJson,
      endpoint: '/oauth/config',
    );
  }

  /// Starts a GitHub device authorization request on the user's behalf.
  Future<GithubDeviceCodeStarted> startDeviceAuthorization() async {
    final response = await _http.post(_uri('/oauth/device/start'));
    return _decode(
      response,
      GithubDeviceCodeStarted.fromJson,
      endpoint: '/oauth/device/start',
    );
  }

  /// Polls GitHub once for a pending device authorization session.
  Future<GithubDevicePollResult> pollDeviceAuthorization(
    String sessionId,
  ) async {
    final response = await _http.post(
      _uri('/oauth/device/poll'),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, String>{'session_id': sessionId}),
    );
    return _decode(
      response,
      GithubDevicePollResult.fromJson,
      endpoint: '/oauth/device/poll',
    );
  }

  T _decode<T>(
    http.Response response,
    T Function(Map<String, dynamic>) fromJson, {
    required String endpoint,
  }) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpApiException(response.statusCode, _detailOrBody(response.body));
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw MalformedResponseException(endpoint, response.body);
    }
    if (decoded is! Map<String, dynamic>) {
      throw MalformedResponseException(endpoint, response.body);
    }
    return fromJson(decoded);
  }

  /// Extracts the backend's `detail` message when present so errors surface
  /// the operator-facing reason instead of a raw JSON blob.
  String _detailOrBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded['detail'] is String) {
        return decoded['detail'] as String;
      }
    } on FormatException {
      // Non-JSON error body: fall through to the raw text.
    }
    return body;
  }
}
