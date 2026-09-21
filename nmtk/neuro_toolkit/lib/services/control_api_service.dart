import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/models/system_resources.dart';
import 'package:neuro_toolkit/models/pynq_launcher_action_result.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class LauncherControlSettings {
  const LauncherControlSettings({
    required this.logLevel,
    required this.mujocoAvailable,
    required this.pythonAvailable,
    required this.pynqBoards,
    required this.akidaHosts,
    required this.selectedAkidaHostId,
    required this.backendDeploymentReady,
    this.selectedBackendDeploymentTarget,
  });

  final String logLevel;
  final bool mujocoAvailable;
  final bool pythonAvailable;
  final List<PynqPairedBoard> pynqBoards;
  final List<AkidaPairedHost> akidaHosts;
  final String? selectedAkidaHostId;
  final bool backendDeploymentReady;
  final DeploymentTarget? selectedBackendDeploymentTarget;

  factory LauncherControlSettings.fromJson(Map<String, dynamic> json) {
    return LauncherControlSettings(
      logLevel: json['logLevel'] is String
          ? json['logLevel'] as String
          : 'info',
      mujocoAvailable: json['mujocoAvailable'] is bool
          ? json['mujocoAvailable'] as bool
          : false,
      pythonAvailable: json['pythonAvailable'] is bool
          ? json['pythonAvailable'] as bool
          : true,
      // Hardware inventories are optional capabilities. A stale record from
      // an older launcher must not prevent the core launcher from opening.
      pynqBoards: _parseOptionalEntries(
        json['pynqBoards'],
        PynqPairedBoard.fromJson,
      ),
      akidaHosts: _parseOptionalEntries(
        json['akidaHosts'],
        AkidaPairedHost.fromJson,
      ),
      selectedAkidaHostId: json['selectedAkidaHostId'] is String
          ? json['selectedAkidaHostId'] as String
          : null,
      backendDeploymentReady: json['backendDeploymentReady'] is bool
          ? json['backendDeploymentReady'] as bool
          : false,
      selectedBackendDeploymentTarget: _parseOptionalEntry(
        json['selectedBackendDeploymentTarget'],
        DeploymentTarget.fromJson,
      ),
    );
  }

  static List<T> _parseOptionalEntries<T>(
    Object? value,
    T Function(Map<String, dynamic>) parser,
  ) {
    if (value is! List<dynamic>) {
      return const <Never>[];
    }
    final parsed = <T>[];
    for (final entry in value.whereType<Map<String, dynamic>>()) {
      final item = _parseOptionalEntry(entry, parser);
      if (item != null) {
        parsed.add(item);
      }
    }
    return List<T>.unmodifiable(parsed);
  }

  static T? _parseOptionalEntry<T>(
    Object? value,
    T Function(Map<String, dynamic>) parser,
  ) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    try {
      return parser(value);
    } on Object {
      return null;
    }
  }

  AkidaPairedHost? get selectedAkidaHost {
    final selectedId = selectedAkidaHostId;
    if (selectedId == null) {
      return null;
    }
    for (final host in akidaHosts) {
      if (host.id == selectedId) {
        return host;
      }
    }
    return null;
  }
}

class ControlApiService {
  ControlApiService({
    http.Client? client,
    required Uri baseUri,
    AnalyticsService? analyticsService,
    String adminToken = '',
  }) : _client = _LoggedHttpClient(
         client ?? http.Client(),
         analyticsService,
         adminToken,
       ),
       _baseUri = baseUri,
       _adminToken = adminToken;

  final http.Client _client;
  final Uri _baseUri;
  final String _adminToken;

  Uri get baseUri => _baseUri;

  // Base URI + admin token fully determine what this service does, so two
  // instances that agree on them are interchangeable. Riverpod compares
  // provider values with `==`; without this, selectedControlApiServiceProvider
  // emitted a "new" service on every ConnectNotifier write and cascaded a
  // rebuild into moduleProvider while it was still building (CEL-270).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ControlApiService &&
          other._baseUri == _baseUri &&
          other._adminToken == _adminToken;

  @override
  int get hashCode => Object.hash(_baseUri, _adminToken);

  static String get configuredBaseUrl => const String.fromEnvironment(
    'NMTK_CONTROL_API_BASE_URL',
    defaultValue: '',
  );

  static int get configuredPort =>
      const int.fromEnvironment('NMTK_CONTROL_API_PORT', defaultValue: 8090);

  static Uri normalizeBaseUri(String input) {
    var value = input.trim();
    if (value.isEmpty) {
      throw const FormatException('Enter a server host or IP address.');
    }
    if (!value.contains('://')) {
      value = 'http://$value';
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host.trim().isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        'Enter a host, IP address, or HTTP(S) launcher URL.',
      );
    }

    return uri.replace(
      port: uri.hasPort ? uri.port : configuredPort,
      path: '',
      query: null,
      fragment: null,
    );
  }

  static String normalizeBaseUrl(String input) {
    return normalizeBaseUri(input).toString();
  }

  static bool isLoopbackHost(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'localhost' ||
        normalized.startsWith('127.') ||
        normalized == '::1' ||
        normalized == '[::1]';
  }

  /// Port suite_api listens on. The launcher control API is a different port
  /// ([configuredPort]) on the same host.
  static const int suiteApiPort = 9000;

  /// Base URI of suite_api, derived from the launcher control host so that a
  /// remote-endpoint setting is honoured. A loopback control host means the
  /// backend is local too.
  Uri get suiteApiBaseUri {
    final isRemote = !isLoopbackHost(_baseUri.host);
    return Uri(
      scheme: isRemote && _baseUri.scheme.isNotEmpty ? _baseUri.scheme : 'http',
      host: isRemote ? _baseUri.host : 'localhost',
      port: suiteApiPort,
    );
  }

  /// The release the running backend reports, or null when it cannot be read.
  ///
  /// `"dev"` is a real answer meaning "built from source, not a release" — the
  /// caller must not offer an update against it. Null means the backend could
  /// not be reached or is too old to report a version; either way, no update.
  Future<String?> fetchBackendVersion() async {
    try {
      final response = await _client
          .get(suiteApiBaseUri.replace(path: '/api/suite/health'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return null;
      }
      final decoded = await _readJsonResponse(response);
      final version = decoded['version'];
      if (version is! String || version.trim().isEmpty) {
        return null;
      }
      return version.trim();
    } catch (_) {
      // Version reporting is strictly informational — a backend that cannot
      // answer must never break the screen that asked.
      return null;
    }
  }

  /// Live CPU, memory, optional GPU, and host stats for the server popup.
  ///
  /// Null when the backend is unreachable, too old to expose the route, or
  /// returns an unexpected payload — the popup must degrade quietly.
  Future<SystemResourcesSnapshot?> fetchSystemResources() async {
    try {
      final response = await _client
          .get(suiteApiBaseUri.replace(path: '/api/suite/system/resources'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return null;
      }
      final decoded = await _readJsonResponse(response);
      return SystemResourcesSnapshot.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Uri _uri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return _baseUri.replace(path: normalizedPath);
  }

  /// Unwraps an Akida host from a response that may or may not nest it.
  ///
  /// The routes disagree by design: `/preflight`, `/status`, `/provision`,
  /// `/repair`, and `/restart-services` answer `{"host": {...}, ...}`, while
  /// `/connectivity-test` answers the serialized host directly — and a
  /// serialized host has its own `host` key holding the *address string*. A
  /// blind `payload['host'] as Map?` therefore threw "type 'String' is not a
  /// subtype of type 'Map' in type cast" on exactly the routes that do not nest.
  /// Treat it as the wrapper only when it is one.
  Map<String, dynamic> _akidaHostPayload(Map<String, dynamic> payload) {
    final nested = payload['host'];
    return nested is Map<String, dynamic> ? nested : payload;
  }

  Future<Map<String, dynamic>> _readJsonResponse(http.Response response) async {
    if (response.body.isEmpty) {
      return const <String, dynamic>{};
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw Exception('Unexpected response payload: ${response.body}');
  }

  Future<List<dynamic>> _readJsonList(http.Response response) async {
    final decoded = jsonDecode(response.body);
    if (decoded is List<dynamic>) {
      return decoded;
    }
    throw Exception('Unexpected list payload: ${response.body}');
  }

  Future<void> _ensureSuccess(http.Response response) async {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    final body = response.body;
    throw Exception(
      'Launcher control API error ${response.statusCode}: ${body.isEmpty ? "empty body" : body}',
    );
  }

  Future<bool> isAvailable({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final response = await _client.get(_uri('/health')).timeout(timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<Module>> fetchModules({bool refreshUpdates = false}) async {
    final response = await _client.get(
      _uri('/api/launcher/modules').replace(
        queryParameters: refreshUpdates
            ? const <String, String>{'refreshUpdates': 'true'}
            : null,
      ),
    );
    await _ensureSuccess(response);
    final decoded = await _readJsonList(response);
    return decoded
        .cast<Map<String, dynamic>>()
        .map(Module.fromJson)
        .toList(growable: false);
  }

  Future<Module> fetchModule(String moduleId) async {
    final response = await _client.get(_uri('/api/launcher/modules/$moduleId'));
    await _ensureSuccess(response);
    return Module.fromJson(await _readJsonResponse(response));
  }

  Future<LauncherControlSettings> fetchSettings() async {
    final response = await _client.get(_uri('/api/launcher/settings'));
    await _ensureSuccess(response);
    return LauncherControlSettings.fromJson(await _readJsonResponse(response));
  }

  Future<void> updateSettings({
    String? logLevel,
    String? selectedAkidaHostId,
  }) async {
    final response = await _client.put(
      _uri('/api/launcher/settings'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'logLevel': ?logLevel,
        'selectedAkidaHostId': ?selectedAkidaHostId,
      }),
    );
    await _ensureSuccess(response);
  }

  Future<WorkspaceSnapshot> fetchWorkspace() async {
    final response = await _client.get(_uri('/api/launcher/workspace'));
    await _ensureSuccess(response);
    return WorkspaceSnapshot.fromJson(await _readJsonResponse(response));
  }

  Future<WorkspaceSnapshot> updateWorkspace({
    required List<WorkspaceSession> sessions,
    required String? focusedModuleId,
  }) async {
    final response = await _client.put(
      _uri('/api/launcher/workspace'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessions': sessions.map((session) => session.toJson()).toList(),
        'focusedModuleId': focusedModuleId,
      }),
    );
    await _ensureSuccess(response);
    return WorkspaceSnapshot.fromJson(await _readJsonResponse(response));
  }

  Future<WorkspaceSnapshot> createWorkspaceSession({
    required String moduleId,
    required String surfaceMode,
    String? deepLink,
    Map<String, dynamic> restoreState = const <String, dynamic>{},
    String readinessState = 'opening',
  }) async {
    final response = await _client.post(
      _uri('/api/launcher/workspace/sessions'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'moduleId': moduleId,
        'surfaceMode': surfaceMode,
        'deepLink': deepLink,
        'restoreState': restoreState,
        'readinessState': readinessState,
      }),
    );
    await _ensureSuccess(response);
    return WorkspaceSnapshot.fromJson(await _readJsonResponse(response));
  }

  Future<WorkspaceSnapshot> deleteWorkspaceSession(String moduleId) async {
    final response = await _client.delete(
      _uri('/api/launcher/workspace/sessions/$moduleId'),
    );
    await _ensureSuccess(response);
    return WorkspaceSnapshot.fromJson(await _readJsonResponse(response));
  }

  Future<List<PynqPairedBoard>> fetchPynqBoards() async {
    final response = await _client.get(_uri('/api/launcher/pynq/boards'));
    await _ensureSuccess(response);
    final decoded = await _readJsonList(response);
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(PynqPairedBoard.fromJson)
        .toList(growable: false);
  }

  Future<PynqPairedBoard> createPynqBoard(Map<String, dynamic> payload) async {
    final response = await _client.post(
      _uri('/api/launcher/pynq/boards'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    await _ensureSuccess(response);
    return PynqPairedBoard.fromJson(await _readJsonResponse(response));
  }

  Future<PynqPairedBoard> updatePynqBoard(
    String boardId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _client.put(
      _uri('/api/launcher/pynq/boards/$boardId'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    await _ensureSuccess(response);
    return PynqPairedBoard.fromJson(await _readJsonResponse(response));
  }

  Future<void> deletePynqBoard(String boardId) async {
    final response = await _client.delete(
      _uri('/api/launcher/pynq/boards/$boardId'),
    );
    await _ensureSuccess(response);
  }

  Future<PynqPairedBoard> testPynqBoardConnectivity(String boardId) async {
    final response = await _client.post(
      _uri('/api/launcher/pynq/boards/$boardId/connectivity-test'),
    );
    await _ensureSuccess(response);
    return PynqPairedBoard.fromJson(await _readJsonResponse(response));
  }

  Future<PynqPairedBoard> provisionPynqBoard(String boardId) async {
    final response = await _client.post(
      _uri('/api/launcher/pynq/boards/$boardId/provision'),
    );
    await _ensureSuccess(response);
    final payload = await _readJsonResponse(response);
    final boardJson = payload['board'] as Map<String, dynamic>? ?? payload;
    return PynqPairedBoard.fromJson(boardJson);
  }

  Future<PynqOverlayInstallResult> installPynqOverlay(String boardId) async {
    final response = await _client.post(
      _uri('/api/launcher/pynq/boards/$boardId/install-overlay'),
    );
    await _ensureSuccess(response);
    final payload = await _readJsonResponse(response);
    return PynqOverlayInstallResult.fromJson(payload);
  }

  Future<PynqRestartRuntimeResult> restartPynqRuntime(String boardId) async {
    final response = await _client.post(
      _uri('/api/launcher/pynq/boards/$boardId/restart-runtime'),
    );
    await _ensureSuccess(response);
    final payload = await _readJsonResponse(response);
    return PynqRestartRuntimeResult.fromJson(payload);
  }

  Future<PynqPairedBoard> fetchPynqBoardPreflight(String boardId) async {
    final response = await _client.get(
      _uri('/api/launcher/pynq/boards/$boardId/preflight'),
    );
    await _ensureSuccess(response);
    final payload = await _readJsonResponse(response);
    return PynqPairedBoard.fromJson(payload['board'] as Map<String, dynamic>);
  }

  Future<PynqDeployJob> fetchPynqBoardStatus(String boardId) async {
    final response = await _client.get(
      _uri('/api/launcher/pynq/boards/$boardId/status'),
    );
    await _ensureSuccess(response);
    final payload = await _readJsonResponse(response);
    return PynqDeployJob.fromJson(payload['status'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> proxyPynqDeploy(
    String boardId, {
    required Map<String, dynamic> payload,
  }) async {
    final response = await _client.post(
      _uri('/api/launcher/pynq/boards/$boardId/deploy'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    await _ensureSuccess(response);
    return await _readJsonResponse(response);
  }

  Future<PynqSitlVerifyResult> proxyPynqVerify(
    String boardId, {
    Map<String, dynamic>? payload,
  }) async {
    final response = await _client.post(
      _uri('/api/launcher/pynq/boards/$boardId/verify'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload ?? const <String, dynamic>{}),
    );
    await _ensureSuccess(response);
    return PynqSitlVerifyResult.fromJson(await _readJsonResponse(response));
  }

  Future<List<AkidaPairedHost>> fetchAkidaHosts() async {
    final response = await _client.get(_uri('/api/launcher/akida/hosts'));
    await _ensureSuccess(response);
    final decoded = await _readJsonList(response);
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(AkidaPairedHost.fromJson)
        .toList(growable: false);
  }

  Future<AkidaPairedHost> createAkidaHost(Map<String, dynamic> payload) async {
    final response = await _client.post(
      _uri('/api/launcher/akida/hosts'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    await _ensureSuccess(response);
    return AkidaPairedHost.fromJson(await _readJsonResponse(response));
  }

  Future<AkidaPairedHost> updateAkidaHost(
    String hostId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _client.put(
      _uri('/api/launcher/akida/hosts/$hostId'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    await _ensureSuccess(response);
    return AkidaPairedHost.fromJson(await _readJsonResponse(response));
  }

  Future<void> deleteAkidaHost(String hostId) async {
    final response = await _client.delete(
      _uri('/api/launcher/akida/hosts/$hostId'),
    );
    await _ensureSuccess(response);
  }

  Future<AkidaPairedHost> testAkidaHostConnectivity(String hostId) async {
    final response = await _client.post(
      _uri('/api/launcher/akida/hosts/$hostId/connectivity-test'),
    );
    await _ensureSuccess(response);
    return AkidaPairedHost.fromJson(
      _akidaHostPayload(await _readJsonResponse(response)),
    );
  }

  Future<AkidaPairedHost> provisionAkidaHost(String hostId) async {
    final response = await _client.post(
      _uri('/api/launcher/akida/hosts/$hostId/provision'),
    );
    await _ensureSuccess(response);
    final payload = await _readJsonResponse(response);
    return AkidaPairedHost.fromJson(_akidaHostPayload(payload));
  }

  Future<AkidaRuntimeUpdateJob> startAkidaRuntimeUpdate(String hostId) async {
    final response = await _client.post(
      _uri('/api/launcher/akida/hosts/$hostId/runtime-update-jobs'),
    );
    await _ensureSuccess(response);
    return AkidaRuntimeUpdateJob.fromJson(await _readJsonResponse(response));
  }

  Future<AkidaRuntimeUpdateJob> fetchAkidaRuntimeUpdate(
    String hostId,
    String jobId,
  ) async {
    final response = await _client.get(
      _uri('/api/launcher/akida/hosts/$hostId/runtime-update-jobs/$jobId'),
    );
    await _ensureSuccess(response);
    return AkidaRuntimeUpdateJob.fromJson(await _readJsonResponse(response));
  }

  Future<AkidaPairedHost> repairAkidaHost(String hostId) async {
    final response = await _client.post(
      _uri('/api/launcher/akida/hosts/$hostId/repair'),
    );
    await _ensureSuccess(response);
    final payload = await _readJsonResponse(response);
    return AkidaPairedHost.fromJson(_akidaHostPayload(payload));
  }

  Future<AkidaPairedHost> restartAkidaHostServices(String hostId) async {
    final response = await _client.post(
      _uri('/api/launcher/akida/hosts/$hostId/restart-services'),
    );
    await _ensureSuccess(response);
    final payload = await _readJsonResponse(response);
    return AkidaPairedHost.fromJson(_akidaHostPayload(payload));
  }

  Future<AkidaPairedHost> fetchAkidaHostPreflight(String hostId) async {
    final response = await _client.get(
      _uri('/api/launcher/akida/hosts/$hostId/preflight'),
    );
    await _ensureSuccess(response);
    final payload = await _readJsonResponse(response);
    return AkidaPairedHost.fromJson(_akidaHostPayload(payload));
  }

  Future<AkidaPairedHost> fetchAkidaHostStatus(String hostId) async {
    final response = await _client.get(
      _uri('/api/launcher/akida/hosts/$hostId/status'),
    );
    await _ensureSuccess(response);
    final payload = await _readJsonResponse(response);
    return AkidaPairedHost.fromJson(_akidaHostPayload(payload));
  }

  Future<Module> installModule(String moduleId) async {
    final response = await _client.post(
      _uri('/api/launcher/modules/$moduleId/install'),
    );
    await _ensureSuccess(response);
    return Module.fromJson(await _readJsonResponse(response));
  }

  Future<Module> startModule(String moduleId) async {
    final response = await _client.post(
      _uri('/api/launcher/modules/$moduleId/start'),
    );
    await _ensureSuccess(response);
    return Module.fromJson(await _readJsonResponse(response));
  }

  Future<Module> stopModule(String moduleId) async {
    final response = await _client.post(
      _uri('/api/launcher/modules/$moduleId/stop'),
    );
    await _ensureSuccess(response);
    return Module.fromJson(await _readJsonResponse(response));
  }

  Future<Module> uninstallModule(String moduleId) async {
    final response = await _client.post(
      _uri('/api/launcher/modules/$moduleId/uninstall'),
    );
    await _ensureSuccess(response);
    return Module.fromJson(await _readJsonResponse(response));
  }

  Future<Module> updateModule(String moduleId) async {
    final response = await _client.post(
      _uri('/api/launcher/modules/$moduleId/update'),
    );
    await _ensureSuccess(response);
    return Module.fromJson(await _readJsonResponse(response));
  }

  Future<Module> repairModule(String moduleId) async {
    final response = await _client.post(
      _uri('/api/launcher/modules/$moduleId/repair'),
    );
    await _ensureSuccess(response);
    return Module.fromJson(await _readJsonResponse(response));
  }

  Future<Module> prepareAkidaRuntime(String moduleId) async {
    final response = await _client.post(
      _uri('/api/launcher/modules/$moduleId/akida-runtime/prepare'),
    );
    await _ensureSuccess(response);
    return Module.fromJson(await _readJsonResponse(response));
  }

  Future<Module> updateModuleSettings(
    String moduleId, {
    bool? isEnabled,
    int? customPort,
    bool? versionPinned,
    bool? startOnLaunch,
  }) async {
    final response = await _client.put(
      _uri('/api/launcher/modules/$moduleId/settings'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'isEnabled': ?isEnabled,
        'customPort': customPort,
        'versionPinned': ?versionPinned,
        'startOnLaunch': ?startOnLaunch,
      }),
    );
    await _ensureSuccess(response);
    return Module.fromJson(await _readJsonResponse(response));
  }

  Future<List<String>> fetchBackendLogs({bool errorOnly = false}) async {
    final response = await _client.get(
      _uri('/api/launcher/logs').replace(
        queryParameters: errorOnly
            ? const <String, String>{'filter': 'error'}
            : null,
      ),
    );
    await _ensureSuccess(response);
    final decoded = await _readJsonResponse(response);
    final lines = decoded['lines'];
    if (lines is List) {
      return lines.cast<String>();
    }
    throw Exception('Unexpected logs payload: ${response.body}');
  }

  /// Fetches the Dart AnalyticsService crash.log via the launcher control
  /// service, which can read ~/Documents/ regardless of app sandbox state.
  Future<List<String>> fetchCrashLogLines() async {
    final response = await _client.get(_uri('/api/launcher/crash-log'));
    await _ensureSuccess(response);
    final decoded = await _readJsonResponse(response);
    final lines = decoded['lines'];
    if (lines is List) {
      return lines.cast<String>();
    }
    throw Exception('Unexpected crash-log payload: ${response.body}');
  }

  /// Fetches the launcher_backend_activity.log via the launcher control
  /// service. Pass [errorOnly] to receive only error/4xx/5xx lines.
  Future<List<String>> fetchBackendActivityLogLines({
    bool errorOnly = false,
  }) async {
    final response = await _client.get(
      _uri('/api/launcher/backend-activity-log').replace(
        queryParameters: errorOnly
            ? const <String, String>{'filter': 'error'}
            : null,
      ),
    );
    await _ensureSuccess(response);
    final decoded = await _readJsonResponse(response);
    final lines = decoded['lines'];
    if (lines is List) {
      return lines.cast<String>();
    }
    throw Exception(
      'Unexpected backend-activity-log payload: ${response.body}',
    );
  }
}

class _LoggedHttpClient extends http.BaseClient {
  _LoggedHttpClient(this._inner, this._analytics, this._adminToken);

  static const _requestTimeout = Duration(seconds: 10);

  final http.Client _inner;
  final AnalyticsService? _analytics;
  final String _adminToken;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_adminToken.isNotEmpty) {
      request.headers['X-NMTK-Admin-Token'] = _adminToken;
    }
    final stopwatch = Stopwatch()..start();
    final requestBody = _requestBody(request);
    try {
      final response = await _inner
          .send(request)
          .timeout(
            _requestTimeout,
            onTimeout: () => throw TimeoutException(
              'Control API request timed out: ${request.method} ${request.url}',
              _requestTimeout,
            ),
          );
      final bytes = await response.stream.toBytes().timeout(
        _requestTimeout,
        onTimeout: () => throw TimeoutException(
          'Control API response body timed out: '
          '${request.method} ${request.url}',
          _requestTimeout,
        ),
      );
      stopwatch.stop();
      final responseBody = utf8.decode(bytes, allowMalformed: true);
      await _analytics?.recordBackendActivity(
        method: request.method,
        uri: request.url,
        statusCode: response.statusCode,
        requestBody: requestBody,
        responseBody: responseBody,
        duration: stopwatch.elapsed,
      );
      return http.StreamedResponse(
        http.ByteStream(Stream<List<int>>.value(bytes)),
        response.statusCode,
        contentLength: bytes.length,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (error) {
      stopwatch.stop();
      await _analytics?.recordBackendActivity(
        method: request.method,
        uri: request.url,
        requestBody: requestBody,
        error: error,
        duration: stopwatch.elapsed,
      );
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
  }

  String? _requestBody(http.BaseRequest request) {
    if (request is http.Request) {
      return request.body;
    }
    if (request is http.MultipartRequest) {
      return jsonEncode({
        'fields': request.fields,
        'files': request.files.map((file) => file.filename).toList(),
      });
    }
    return null;
  }
}
