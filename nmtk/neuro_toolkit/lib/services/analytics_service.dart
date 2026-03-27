import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  bool _telemetryEnabled = false;
  String? _remoteEndpoint;
  File? _logFile;

  set telemetryEnabled(bool enabled) => _telemetryEnabled = enabled;
  set remoteEndpoint(String? endpoint) => _remoteEndpoint = endpoint;

  Future<void> init() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      _logFile = File(p.join(directory.path, 'crash.log'));
    } catch (e) {
      debugPrint('Failed to initialize analytics log file: $e');
    }
  }

  Future<void> logCrash(Object error, StackTrace stackTrace) async {
    final timestamp = DateTime.now().toIso8601String();
    final logEntry = '[$timestamp] FATAL ERROR: $error\n$stackTrace\n\n';

    // Always log locally
    if (_logFile != null) {
      try {
        await _logFile!.writeAsString(logEntry, mode: FileMode.append);
      } catch (e) {
        debugPrint('Failed to write to local crash log: $e');
      }
    }

    // Optional remote reporting
    if (_remoteEndpoint != null && _remoteEndpoint!.isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse(_remoteEndpoint!),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'timestamp': timestamp,
                'type': 'crash',
                'error': error.toString(),
                'stackTrace': stackTrace.toString(),
              }),
            )
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('Failed to send remote crash report: $e');
      }
    }
  }

  Future<void> trackEvent(String name,
      {Map<String, dynamic>? properties}) async {
    if (!_telemetryEnabled) return;

    final timestamp = DateTime.now().toIso8601String();
    debugPrint('Analytics Event: $name $properties');

    if (_remoteEndpoint != null && _remoteEndpoint!.isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse(_remoteEndpoint!),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'timestamp': timestamp,
                'type': 'event',
                'name': name,
                'properties': properties ?? {},
              }),
            )
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('Failed to send remote telemetry: $e');
      }
    }
  }

  Future<String> getLocalLogs() async {
    if (_logFile == null || !await _logFile!.exists()) {
      return 'No logs found.';
    }
    return await _logFile!.readAsString();
  }

  Future<void> clearLocalLogs() async {
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.delete();
    }
  }
}
