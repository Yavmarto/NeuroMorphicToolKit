import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:neuro_toolkit/features/neurocnl/config/app_config.dart';
import 'package:neuro_toolkit/features/neurocnl/services/base_http_client.dart';

/// Thrown for any non-success Neurohub API response other than a workspace
/// save conflict (see [NeurohubConflictException]).
class NeurohubException implements Exception {
  const NeurohubException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'NeurohubException($statusCode): $message';
}

/// A workspace save was rejected because [baseCommit] is no longer the
/// branch tip. Recovery is always one of reload, save a copy, or resolve.
class NeurohubConflictException implements Exception {
  const NeurohubConflictException({
    required this.baseCommit,
    required this.remoteCommit,
    required this.recovery,
  });

  final String baseCommit;
  final String remoteCommit;
  final List<String> recovery;

  @override
  String toString() =>
      'NeurohubConflictException(base: $baseCommit, remote: $remoteCommit)';
}

class NeurohubDeviceFlowConfig {
  const NeurohubDeviceFlowConfig({
    required this.clientId,
    required this.scopes,
  });

  final String clientId;
  final List<String> scopes;

  factory NeurohubDeviceFlowConfig.fromJson(Map<String, dynamic> json) {
    return NeurohubDeviceFlowConfig(
      clientId: json['client_id'] as String,
      scopes: List<String>.from((json['scopes'] as List?) ?? const []),
    );
  }
}

class NeurohubDeviceCodeStarted {
  const NeurohubDeviceCodeStarted({
    required this.sessionId,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  final String sessionId;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;

  factory NeurohubDeviceCodeStarted.fromJson(Map<String, dynamic> json) {
    return NeurohubDeviceCodeStarted(
      sessionId: json['session_id'] as String,
      userCode: json['user_code'] as String,
      verificationUri: json['verification_uri'] as String,
      expiresIn: json['expires_in'] as int,
      interval: json['interval'] as int,
    );
  }
}

/// One poll outcome. [status] is one of pending, slow_down, expired, denied,
/// or success; [accessToken] is only set on success.
class NeurohubDevicePollResult {
  const NeurohubDevicePollResult({
    required this.status,
    this.accessToken,
    this.interval,
  });

  final String status;
  final String? accessToken;
  final int? interval;

  bool get isSuccess => status == 'success';
  bool get isTerminal =>
      status == 'success' || status == 'expired' || status == 'denied';

  factory NeurohubDevicePollResult.fromJson(Map<String, dynamic> json) {
    return NeurohubDevicePollResult(
      status: json['status'] as String,
      accessToken: json['access_token'] as String?,
      interval: json['interval'] as int?,
    );
  }
}

class NeurohubWorkspaceSummary {
  const NeurohubWorkspaceSummary({
    required this.owner,
    required this.slug,
    required this.displayName,
    required this.description,
    required this.tags,
    required this.private,
    required this.archived,
    required this.updatedAt,
    required this.headCommit,
    required this.repositoryUrl,
    required this.permission,
    required this.neurohubUri,
  });

  final String owner;
  final String slug;
  final String displayName;
  final String description;
  final List<String> tags;
  final bool private;
  final bool archived;
  final String updatedAt;
  final String headCommit;
  final String repositoryUrl;
  final String permission;
  final String neurohubUri;

  factory NeurohubWorkspaceSummary.fromJson(Map<String, dynamic> json) {
    return NeurohubWorkspaceSummary(
      owner: json['owner'] as String,
      slug: json['slug'] as String,
      displayName: json['display_name'] as String,
      description: json['description'] as String? ?? '',
      tags: List<String>.from((json['tags'] as List?) ?? const []),
      private: json['private'] as bool,
      archived: json['archived'] as bool? ?? false,
      updatedAt: json['updated_at'] as String,
      headCommit: json['head_commit'] as String,
      repositoryUrl: json['repository_url'] as String,
      permission: json['permission'] as String? ?? 'read',
      neurohubUri: json['neurohub_uri'] as String,
    );
  }
}

/// A workspace summary plus its current document payload.
class NeurohubWorkspace extends NeurohubWorkspaceSummary {
  const NeurohubWorkspace({
    required super.owner,
    required super.slug,
    required super.displayName,
    required super.description,
    required super.tags,
    required super.private,
    required super.archived,
    required super.updatedAt,
    required super.headCommit,
    required super.repositoryUrl,
    required super.permission,
    required super.neurohubUri,
    required this.workspace,
  });

  /// The raw `workspace.nmtk.json` document.
  final Map<String, dynamic> workspace;

  factory NeurohubWorkspace.fromJson(Map<String, dynamic> json) {
    final summary = NeurohubWorkspaceSummary.fromJson(json);
    return NeurohubWorkspace(
      owner: summary.owner,
      slug: summary.slug,
      displayName: summary.displayName,
      description: summary.description,
      tags: summary.tags,
      private: summary.private,
      archived: summary.archived,
      updatedAt: summary.updatedAt,
      headCommit: summary.headCommit,
      repositoryUrl: summary.repositoryUrl,
      permission: summary.permission,
      neurohubUri: summary.neurohubUri,
      workspace: Map<String, dynamic>.from(
        (json['workspace'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }
}

/// HTTP client for the one central Neurohub API.
///
/// Every workspace call is proxied through Neurohub to GitHub server-side —
/// this client never talks to GitHub directly, only to [AppConfig.neurohubApiUrl]
/// (or an injected [baseUrl] in tests). Pass [accessToken] once the device-flow
/// sign-in completes; requests made without one only reach the public
/// endpoints (`oauth/config`, `oauth/device/*`, `oauth/health`).
class NeurohubClient extends BaseHttpClient {
  NeurohubClient({String? baseUrl, super.httpClient, this.accessToken})
    : super(baseUrl: baseUrl ?? AppConfig.neurohubApiUrl);

  String? accessToken;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (accessToken != null) 'Authorization': 'Bearer $accessToken',
  };

  void _ensureConfigured() {
    if (baseUrl.isEmpty) {
      throw const NeurohubException(
        503,
        'Neurohub is not configured. Set NEUROHUB_API_URL.',
      );
    }
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Set<int> expected = const {200},
  }) async {
    _ensureConfigured();
    final uri = buildUri(path);
    final request = http.Request(method, uri);
    request.headers.addAll(_headers);
    if (body != null) {
      request.body = jsonEncode(body);
    }
    final streamed = await rawHttpClient.send(request);
    final responseBody = await streamed.stream.bytesToString();
    if (!expected.contains(streamed.statusCode)) {
      _throwForStatus(streamed.statusCode, responseBody);
    }
    if (responseBody.isEmpty) {
      return const {};
    }
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw NeurohubException(
        streamed.statusCode,
        'Expected a JSON object: $responseBody',
      );
    }
    return decoded;
  }

  Never _throwForStatus(int statusCode, String body) {
    if (statusCode == 409) {
      final decoded = jsonDecode(body);
      final detail = (decoded is Map ? decoded['detail'] : null) ?? decoded;
      if (detail is Map && detail['code'] == 'workspace_conflict') {
        throw NeurohubConflictException(
          baseCommit: detail['base_commit'] as String,
          remoteCommit: detail['remote_commit'] as String,
          recovery: List<String>.from(
            (detail['recovery'] as List?) ?? const [],
          ),
        );
      }
    }
    String message = body;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] is String) {
        message = decoded['detail'] as String;
      }
    } catch (_) {
      // Non-JSON error body: fall back to the raw text.
    }
    throw NeurohubException(statusCode, message);
  }

  // ── OAuth Device Flow ──────────────────────────────────────────

  Future<NeurohubDeviceFlowConfig> oauthConfig() async {
    final json = await _send('GET', '/api/neurohub/oauth/config');
    return NeurohubDeviceFlowConfig.fromJson(json);
  }

  Future<NeurohubDeviceCodeStarted> startDeviceAuthorization() async {
    final json = await _send(
      'POST',
      '/api/neurohub/oauth/device/start',
      expected: {200},
    );
    return NeurohubDeviceCodeStarted.fromJson(json);
  }

  Future<NeurohubDevicePollResult> pollDeviceAuthorization(
    String sessionId,
  ) async {
    final json = await _send(
      'POST',
      '/api/neurohub/oauth/device/poll',
      body: {'session_id': sessionId},
    );
    return NeurohubDevicePollResult.fromJson(json);
  }

  // ── Workspaces ──────────────────────────────────────────────────

  Future<List<NeurohubWorkspaceSummary>> listWorkspaces() async {
    _ensureConfigured();
    final uri = buildUri('/api/neurohub/workspaces');
    final response = await rawHttpClient.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      _throwForStatus(response.statusCode, response.body);
    }
    final decoded = decodeBodyAsList(response);
    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (item) =>
              NeurohubWorkspaceSummary.fromJson(item.cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  Future<NeurohubWorkspace> createWorkspace({
    required String slug,
    required String displayName,
    required Map<String, dynamic> workspace,
    String description = '',
    List<String> tags = const [],
    bool private = true,
  }) async {
    final json = await _send(
      'POST',
      '/api/neurohub/workspaces',
      body: {
        'slug': slug,
        'display_name': displayName,
        'description': description,
        'tags': tags,
        'workspace': workspace,
        'private': private,
      },
      expected: {201},
    );
    return NeurohubWorkspace.fromJson(json);
  }

  Future<NeurohubWorkspace> getWorkspace(String owner, String slug) async {
    final json = await _send('GET', '/api/neurohub/workspaces/$owner/$slug');
    return NeurohubWorkspace.fromJson(json);
  }

  /// Saves one atomic revision. Throws [NeurohubConflictException] if
  /// [baseCommit] is no longer the branch tip.
  Future<NeurohubWorkspace> updateWorkspace(
    String owner,
    String slug, {
    required String baseCommit,
    required Map<String, dynamic> workspace,
    String? displayName,
    String? description,
    List<String>? tags,
    String message = 'Save workspace',
  }) async {
    final json = await _send(
      'PUT',
      '/api/neurohub/workspaces/$owner/$slug',
      body: {
        'base_commit': baseCommit,
        'workspace': workspace,
        'display_name': ?displayName,
        'description': ?description,
        'tags': ?tags,
        'message': message,
      },
    );
    return NeurohubWorkspace.fromJson(json);
  }

  Future<void> addCollaborator(
    String owner,
    String slug,
    String username, {
    String permission = 'write',
  }) async {
    await _send(
      'PUT',
      '/api/neurohub/workspaces/$owner/$slug/collaborators/$username',
      body: {'permission': permission},
      expected: {204},
    );
  }

  Future<void> removeCollaborator(
    String owner,
    String slug,
    String username,
  ) async {
    await _send(
      'DELETE',
      '/api/neurohub/workspaces/$owner/$slug/collaborators/$username',
      expected: {204},
    );
  }

  Future<NeurohubWorkspace> setVisibility(
    String owner,
    String slug, {
    required bool public,
  }) async {
    final json = await _send(
      'POST',
      '/api/neurohub/workspaces/$owner/$slug/visibility',
      body: {'public': public},
    );
    return NeurohubWorkspace.fromJson(json);
  }

  Future<void> archiveWorkspace(String owner, String slug) async {
    await _send(
      'DELETE',
      '/api/neurohub/workspaces/$owner/$slug',
      expected: {204},
    );
  }
}
