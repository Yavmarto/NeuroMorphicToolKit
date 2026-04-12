import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:neuro_toolkit/models/module.dart';

class LauncherControlSettings {
  const LauncherControlSettings({
    required this.logLevel,
    required this.mujocoAvailable,
    required this.pythonAvailable,
  });

  final String logLevel;
  final bool mujocoAvailable;
  final bool pythonAvailable;

  factory LauncherControlSettings.fromJson(Map<String, dynamic> json) {
    return LauncherControlSettings(
      logLevel: json['logLevel'] as String? ?? 'info',
      mujocoAvailable: json['mujocoAvailable'] as bool? ?? false,
      pythonAvailable: json['pythonAvailable'] as bool? ?? true,
    );
  }
}

class ControlApiService {
  ControlApiService({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? _resolveBaseUri();

  final http.Client _client;
  final Uri _baseUri;

  static Uri _resolveBaseUri() {
    const configuredBaseUrl =
        String.fromEnvironment('NMTK_CONTROL_API_BASE_URL', defaultValue: '');
    if (configuredBaseUrl.isNotEmpty) {
      return Uri.parse(configuredBaseUrl);
    }

    const configuredPort =
        int.fromEnvironment('NMTK_CONTROL_API_PORT', defaultValue: 8090);

    if (kIsWeb) {
      final baseHost = Uri.base.host.trim();
      final host =
          baseHost.isEmpty || baseHost == '0.0.0.0' ? 'localhost' : baseHost;
      final scheme = Uri.base.scheme.trim().isEmpty ? 'http' : Uri.base.scheme;
      return Uri(scheme: scheme, host: host, port: configuredPort);
    }

    return Uri.parse('http://127.0.0.1:$configuredPort');
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

  Future<List<Module>> fetchModules() async {
    final response = await _client.get(_uri('/api/launcher/modules'));
    await _ensureSuccess(response);
    final decoded = await _readJsonList(response);
    return decoded
        .cast<Map<String, dynamic>>()
        .map(Module.fromJson)
        .toList(growable: false);
  }

  Future<Module> fetchModule(String moduleId) async {
    final response = await _client.get(
      _uri('/api/launcher/modules/$moduleId'),
    );
    await _ensureSuccess(response);
    return Module.fromJson(await _readJsonResponse(response));
  }

  Future<LauncherControlSettings> fetchSettings() async {
    final response = await _client.get(_uri('/api/launcher/settings'));
    await _ensureSuccess(response);
    return LauncherControlSettings.fromJson(await _readJsonResponse(response));
  }

  Future<void> updateSettings({String? logLevel}) async {
    final response = await _client.put(
      _uri('/api/launcher/settings'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (logLevel != null) 'logLevel': logLevel,
      }),
    );
    await _ensureSuccess(response);
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

  Future<Module> updateModuleSettings(
    String moduleId, {
    bool? isEnabled,
    int? customPort,
    bool? versionPinned,
  }) async {
    final response = await _client.put(
      _uri('/api/launcher/modules/$moduleId/settings'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (isEnabled != null) 'isEnabled': isEnabled,
        'customPort': customPort,
        if (versionPinned != null) 'versionPinned': versionPinned,
      }),
    );
    await _ensureSuccess(response);
    return Module.fromJson(await _readJsonResponse(response));
  }
}
