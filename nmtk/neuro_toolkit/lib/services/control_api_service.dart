import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/models/pynq_launcher_action_result.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

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
      logLevel: json['logLevel'] as String? ?? 'info',
      mujocoAvailable: json['mujocoAvailable'] as bool? ?? false,
      pythonAvailable: json['pythonAvailable'] as bool? ?? true,
      pynqBoards: (json['pynqBoards'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(PynqPairedBoard.fromJson)
          .toList(growable: false),
      akidaHosts: (json['akidaHosts'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AkidaPairedHost.fromJson)
          .toList(growable: false),
      selectedAkidaHostId: json['selectedAkidaHostId'] as String?,
      backendDeploymentReady: json['backendDeploymentReady'] as bool? ?? false,
      selectedBackendDeploymentTarget: json['selectedBackendDeploymentTarget']
              is Map<String, dynamic>
          ? DeploymentTarget.fromJson(
              json['selectedBackendDeploymentTarget'] as Map<String, dynamic>,
            )
          : null,
    );
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
  ControlApiService({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? resolveBaseUri();

  final http.Client _client;
  final Uri _baseUri;

  Uri get baseUri => _baseUri;

  static String get configuredBaseUrl => const String.fromEnvironment(
        'NMTK_CONTROL_API_BASE_URL',
        defaultValue: '',
      );

  static int get configuredPort => const int.fromEnvironment(
        'NMTK_CONTROL_API_PORT',
        defaultValue: 8090,
      );

  static Uri resolveBaseUri({Uri? fallbackBaseUri}) {
    final configuredBaseUrl = ControlApiService.configuredBaseUrl;
    if (configuredBaseUrl.isNotEmpty) {
      return Uri.parse(configuredBaseUrl);
    }

    if (fallbackBaseUri != null) {
      return fallbackBaseUri;
    }

    if (kIsWeb) {
      final baseHost = Uri.base.host.trim();
      final host =
          baseHost.isEmpty || baseHost == '0.0.0.0' ? 'localhost' : baseHost;
      final scheme = Uri.base.scheme.trim().isEmpty ? 'http' : Uri.base.scheme;
      return Uri(
          scheme: scheme, host: host, port: ControlApiService.configuredPort);
    }

    return Uri.parse('http://127.0.0.1:${ControlApiService.configuredPort}');
  }

  static String normalizeBaseUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) {
      return value;
    }
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static bool isLoopbackHost(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1' ||
        normalized == '[::1]';
  }

  Uri _uri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return _baseUri.replace(path: normalizedPath);
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

  Future<bool> isAvailable() async {
    try {
      final response = await _client.get(_uri('/health'));
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

  Future<List<DeploymentTarget>> fetchDeploymentTargets() async {
    final response =
        await _client.get(_uri('/api/launcher/deployment/targets'));
    await _ensureSuccess(response);
    final decoded = await _readJsonList(response);
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(DeploymentTarget.fromJson)
        .toList(growable: false);
  }

  Future<DeploymentTarget> createDeploymentTarget(
    Map<String, dynamic> payload,
  ) async {
    final response = await _client.post(
      _uri('/api/launcher/deployment/targets'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    await _ensureSuccess(response);
    return DeploymentTarget.fromJson(await _readJsonResponse(response));
  }

  Future<DeploymentPreflightResult> preflightDeploymentTarget(
    Map<String, dynamic> payload,
  ) async {
    final response = await _client.post(
      _uri('/api/launcher/deployment/preflight'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    await _ensureSuccess(response);
    return DeploymentPreflightResult.fromJson(
      await _readJsonResponse(response),
    );
  }

  Future<DeploymentJob> createDeploymentJob(
      Map<String, dynamic> payload) async {
    final response = await _client.post(
      _uri('/api/launcher/deployment/jobs'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    await _ensureSuccess(response);
    return DeploymentJob.fromJson(await _readJsonResponse(response));
  }

  Future<DeploymentJob> fetchDeploymentJob(String jobId) async {
    final response =
        await _client.get(_uri('/api/launcher/deployment/jobs/$jobId'));
    await _ensureSuccess(response);
    return DeploymentJob.fromJson(await _readJsonResponse(response));
  }

  Future<DeploymentJob> cancelDeploymentJob(String jobId) async {
    final response =
        await _client.post(_uri('/api/launcher/deployment/jobs/$jobId/cancel'));
    await _ensureSuccess(response);
    return DeploymentJob.fromJson(await _readJsonResponse(response));
  }

  Future<void> updateSettings({
    String? logLevel,
    String? selectedAkidaHostId,
  }) async {
    final response = await _client.put(
      _uri('/api/launcher/settings'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (logLevel != null) 'logLevel': logLevel,
        if (selectedAkidaHostId != null)
          'selectedAkidaHostId': selectedAkidaHostId,
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
    return AkidaPairedHost.fromJson(await _readJsonResponse(response));
  }

  Future<AkidaPairedHost> provisionAkidaHost(String hostId) async {
    final response = await _client.post(
      _uri('/api/launcher/akida/hosts/$hostId/provision'),
    );
    await _ensureSuccess(response);
    final payload = await _readJsonResponse(response);
    final hostJson = payload['host'] as Map<String, dynamic>? ?? payload;
    return AkidaPairedHost.fromJson(hostJson);
  }

  Future<AkidaPairedHost> repairAkidaHost(String hostId) async {
    final response = await _client.post(
      _uri('/api/launcher/akida/hosts/$hostId/repair'),
    );
    await _ensureSuccess(response);
    final payload = await _readJsonResponse(response);
    final hostJson = payload['host'] as Map<String, dynamic>? ?? payload;
    return AkidaPairedHost.fromJson(hostJson);
  }

  Future<AkidaPairedHost> restartAkidaHostServices(String hostId) async {
    final response = await _client.post(
      _uri('/api/launcher/akida/hosts/$hostId/restart-services'),
    );
    await _ensureSuccess(response);
    final payload = await _readJsonResponse(response);
    final hostJson = payload['host'] as Map<String, dynamic>? ?? payload;
    return AkidaPairedHost.fromJson(hostJson);
  }

  Future<AkidaPairedHost> fetchAkidaHostPreflight(String hostId) async {
    final response = await _client.get(
      _uri('/api/launcher/akida/hosts/$hostId/preflight'),
    );
    await _ensureSuccess(response);
    final payload = await _readJsonResponse(response);
    final hostJson = payload['host'] as Map<String, dynamic>? ?? payload;
    return AkidaPairedHost.fromJson(hostJson);
  }

  Future<AkidaPairedHost> fetchAkidaHostStatus(String hostId) async {
    final response = await _client.get(
      _uri('/api/launcher/akida/hosts/$hostId/status'),
    );
    await _ensureSuccess(response);
    final payload = await _readJsonResponse(response);
    final hostJson = payload['host'] as Map<String, dynamic>? ?? payload;
    return AkidaPairedHost.fromJson(hostJson);
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
        if (isEnabled != null) 'isEnabled': isEnabled,
        'customPort': customPort,
        if (versionPinned != null) 'versionPinned': versionPinned,
        if (startOnLaunch != null) 'startOnLaunch': startOnLaunch,
      }),
    );
    await _ensureSuccess(response);
    return Module.fromJson(await _readJsonResponse(response));
  }

  Future<List<String>> fetchBackendLogs({bool errorOnly = false}) async {
    final response = await _client.get(
      _uri('/api/launcher/logs').replace(
        queryParameters: errorOnly ? const <String, String>{'filter': 'error'} : null,
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
}
