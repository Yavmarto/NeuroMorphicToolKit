import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:neuro_toolkit/features/server/shared/target_store.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';

/// Thrown when a login attempt is rejected or the launcher cannot be reached.
class ConnectException implements Exception {
  const ConnectException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A live session against one launcher host.
class ConnectSession {
  const ConnectSession({
    required this.host,
    required this.username,
    required this.sessionToken,
  });

  final String host;
  final String username;
  final String sessionToken;
}

/// The every-launch, credential-only connect path: one HTTP call to an
/// already-running launcher. No SSH, no sudo, no runtime detection — see the
/// CEL-25 plan document's provision/connect split. Provisioning a server
/// (installing the backend) is [ProvisionService]'s job, not this one's.
class ConnectService {
  ConnectService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  /// Logs in against [host] with an app username and its password and returns
  /// a short-lived session token.
  ///
  /// Calls the backend's `POST /api/launcher/auth/login`, which bcrypt-checks
  /// [credential] against the app user the server was provisioned with (see
  /// CEL-26). The wire field is `password`; the Dart parameter keeps the
  /// `credential` name from the CEL-25 plan so a passkey variant can slot in
  /// without renaming callers later.
  Future<ConnectSession> login({
    required String host,
    required String username,
    required String credential,
  }) async {
    final Uri baseUri;
    try {
      baseUri = ControlApiService.normalizeBaseUri(host);
    } on FormatException catch (error) {
      throw ConnectException(error.message);
    }

    http.Response response;
    try {
      response = await _httpClient
          .post(
            baseUri.replace(path: '/api/launcher/auth/login'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(<String, String>{
              'username': username,
              'password': credential,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } on Object {
      throw ConnectException(
        'Could not reach ${baseUri.host}. Confirm the address and that the '
        'server is running, then try again.',
      );
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const ConnectException('Incorrect username or password.');
    }
    if (response.statusCode != 200) {
      throw ConnectException(
        'The server rejected the login (HTTP ${response.statusCode}).',
      );
    }

    Object? payload;
    try {
      payload = jsonDecode(response.body);
    } on FormatException {
      throw const ConnectException(
        'The server returned an unexpected response.',
      );
    }
    final token = payload is Map<String, dynamic> ? payload['token'] : null;
    if (token is! String || token.isEmpty) {
      throw const ConnectException(
        'The server did not return a session token.',
      );
    }
    return ConnectSession(
      host: baseUri.host,
      username: username,
      sessionToken: token,
    );
  }

  /// Re-authenticates a previously saved [target] on app open by re-logging
  /// in with the saved app password — the backend only accepts a password
  /// (bcrypt-checked against the provisioned app user), so the saved
  /// credential, not the session token, is what re-establishes a session.
  /// Throws [ConnectException] when no credential is saved — the caller
  /// falls back to the connect form.
  Future<ConnectSession> reconnect(ConnectTarget target) {
    if (target.credential.isEmpty) {
      throw const ConnectException(
        'No saved credential for this server. Log in again.',
      );
    }
    return login(
      host: target.host,
      username: target.appUsername,
      credential: target.credential,
    );
  }

  /// Liveness probe for an already-connected host: whether its launcher
  /// answers `GET /health`. Pure connect logic, wrapped as-is from
  /// `server_connection_notifier.dart` (which polled `ControlApiService`
  /// every few seconds) — this module never opens SSH to check.
  Future<bool> probe({
    required String host,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final Uri baseUri;
    try {
      baseUri = ControlApiService.normalizeBaseUri(host);
    } on FormatException {
      return false;
    }
    try {
      final response = await _httpClient
          .get(baseUri.replace(path: '/health'))
          .timeout(timeout);
      return response.statusCode == 200;
    } on Object {
      return false;
    }
  }
}
