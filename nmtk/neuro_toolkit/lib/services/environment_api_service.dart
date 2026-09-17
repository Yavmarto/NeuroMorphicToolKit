import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:neuro_toolkit/services/control_api_service.dart';

/// A Python environment exposed by the Jupyter worker's `nmtk_env_manager`
/// extension. The immutable base ("Python (NeuroStudio)") is flagged via
/// [immutable]; cloned environments are mutable.
@immutable
class EnvironmentInfo {
  const EnvironmentInfo({
    required this.slug,
    required this.displayName,
    required this.kernelName,
    required this.immutable,
    required this.pythonVersion,
    required this.packageCount,
    this.basedOn,
    this.createdAt,
  });

  final String slug;
  final String displayName;
  final String kernelName;
  final bool immutable;
  final String pythonVersion;
  final int packageCount;
  final String? basedOn;
  final String? createdAt;

  factory EnvironmentInfo.fromJson(Map<String, dynamic> json) {
    return EnvironmentInfo(
      slug: json['slug'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      kernelName: json['kernelName'] as String? ?? '',
      immutable: json['immutable'] as bool? ?? false,
      pythonVersion: json['pythonVersion'] as String? ?? 'unknown',
      packageCount: (json['packageCount'] as num?)?.toInt() ?? 0,
      basedOn: json['basedOn'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }
}

/// A single installed package within an environment.
@immutable
class PackageInfo {
  const PackageInfo({required this.name, required this.version});

  final String name;
  final String version;

  factory PackageInfo.fromJson(Map<String, dynamic> json) => PackageInfo(
    name: json['name'] as String? ?? '',
    version: json['version'] as String? ?? '',
  );
}

/// Status of a long-running env operation (create/import/install/uninstall).
@immutable
class EnvJob {
  const EnvJob({required this.id, required this.state, this.error, this.log});

  final String id;
  final String state; // working | ready | error
  final String? error;
  final String? log;

  bool get isDone => state == 'ready' || state == 'error';
  bool get isError => state == 'error';

  factory EnvJob.fromJson(Map<String, dynamic> json) => EnvJob(
    id: json['id'] as String? ?? '',
    state: json['state'] as String? ?? 'working',
    error: json['error'] as String?,
    log: json['log'] as String?,
  );
}

class EnvironmentApiException implements Exception {
  EnvironmentApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to suite_api's `/api/jupyter/environments/*` proxy (port 9000),
/// resolving the host the same way [ToolViewScreen] resolves module URIs so
/// remote-endpoint settings are honoured.
class EnvironmentApiService {
  EnvironmentApiService({
    required ControlApiService controlApi,
    http.Client? client,
  }) : _controlApi = controlApi,
       _client = client ?? http.Client();

  final ControlApiService _controlApi;
  final http.Client _client;

  static const int _suiteApiPort = ControlApiService.suiteApiPort;
  static const Duration _requestTimeout = Duration(seconds: 10);

  Uri _base() {
    if (kIsWeb) {
      final b = Uri.base;
      final host = (b.host.isEmpty || b.host == '0.0.0.0')
          ? 'localhost'
          : b.host;
      final scheme = b.scheme.isEmpty ? 'http' : b.scheme;
      return Uri(scheme: scheme, host: host, port: _suiteApiPort);
    }
    // Single definition of "where suite_api is", shared with
    // ControlApiService.fetchBackendVersion().
    return _controlApi.suiteApiBaseUri;
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      _base().replace(path: '/api/jupyter$path', queryParameters: query);

  String _errorFrom(http.Response r) {
    try {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final err = body['error'];
      if (err is String && err.isNotEmpty) return err;
    } catch (_) {
      /* fall through */
    }
    return 'Request failed (HTTP ${r.statusCode})';
  }

  Future<List<EnvironmentInfo>> listEnvironments() async {
    final r = await _client.get(_uri('/environments')).timeout(_requestTimeout);
    if (r.statusCode != 200) throw EnvironmentApiException(_errorFrom(r));
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (body['environments'] as List<dynamic>? ?? <dynamic>[]);
    return list
        .map((e) => EnvironmentInfo.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<PackageInfo>> listPackages(String slug) async {
    final r = await _client
        .get(_uri('/environments/$slug/packages'))
        .timeout(_requestTimeout);
    if (r.statusCode != 200) throw EnvironmentApiException(_errorFrom(r));
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (body['packages'] as List<dynamic>? ?? <dynamic>[]);
    return list
        .map((e) => PackageInfo.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Returns the job id for the async clone/import.
  Future<String> createEnvironment(String displayName) =>
      _postJob('/environments', {'displayName': displayName});

  Future<String> importEnvironment(String displayName, String requirements) =>
      _postJob('/environments', {
        'displayName': displayName,
        'requirements': requirements,
      });

  Future<String> installPackages(String slug, List<String> specs) => _postJob(
    '/environments/$slug/packages',
    {'action': 'install', 'packages': specs},
  );

  Future<String> uninstallPackages(String slug, List<String> names) => _postJob(
    '/environments/$slug/packages',
    {'action': 'uninstall', 'packages': names},
  );

  Future<String> _postJob(String path, Map<String, dynamic> payload) async {
    final r = await _client
        .post(
          _uri(path),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(_requestTimeout);
    if (r.statusCode != 202) throw EnvironmentApiException(_errorFrom(r));
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final jobId = body['jobId'] as String?;
    if (jobId == null) {
      throw EnvironmentApiException('Backend did not return a job id.');
    }
    return jobId;
  }

  Future<void> deleteEnvironment(String slug) async {
    final r = await _client
        .delete(_uri('/environments/$slug'))
        .timeout(_requestTimeout);
    if (r.statusCode != 204) throw EnvironmentApiException(_errorFrom(r));
  }

  Future<String> exportRequirements(
    String slug, {
    String mode = 'delta',
  }) async {
    final r = await _client
        .get(_uri('/environments/$slug/requirements', {'mode': mode}))
        .timeout(_requestTimeout);
    if (r.statusCode != 200) throw EnvironmentApiException(_errorFrom(r));
    return r.body;
  }

  Future<EnvJob> pollJob(String jobId) async {
    final r = await _client.get(_uri('/jobs/$jobId')).timeout(_requestTimeout);
    if (r.statusCode != 200) throw EnvironmentApiException(_errorFrom(r));
    return EnvJob.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }
}
