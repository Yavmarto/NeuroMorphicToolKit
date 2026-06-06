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
  File? _backendActivityLogFile;

  set telemetryEnabled(bool enabled) => _telemetryEnabled = enabled;
  set remoteEndpoint(String? endpoint) => _remoteEndpoint = endpoint;

  Future<void> init() async {
    try {
      final directory = await getApplicationSupportDirectory();
      _logFile = File(p.join(directory.path, 'crash.log'));
      _backendActivityLogFile =
          File(p.join(directory.path, 'launcher_backend_activity.log'));
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

  Future<List<String>> getLocalLogLines({int maxLines = 2000}) async {
    return _readTailLines(
      _logFile,
      missingMessage: 'No logs found.',
      maxLines: maxLines,
    );
  }

  Future<String> getLocalLogs() async {
    final lines = await getLocalLogLines();
    return lines.join('\n');
  }

  Future<void> recordBackendActivity({
    required String method,
    required Uri uri,
    int? statusCode,
    String? requestBody,
    String? responseBody,
    Object? error,
    Duration? duration,
  }) async {
    final file = _backendActivityLogFile;
    if (file == null) {
      return;
    }

    final buffer = StringBuffer()
      ..writeln(
        '[${DateTime.now().toIso8601String()}] '
        '$method ${uri.toString()} -> ${statusCode ?? 'error'}'
        '${duration == null ? '' : ' (${duration.inMilliseconds} ms)'}',
      );

    final requestSummary = _summarizePayload(requestBody);
    if (requestSummary.isNotEmpty) {
      buffer.writeln('request: $requestSummary');
    }

    final responseSummary = _summarizePayload(responseBody);
    if (responseSummary.isNotEmpty) {
      buffer.writeln('response: $responseSummary');
    }

    if (error != null) {
      buffer.writeln('error: $error');
    }

    buffer.writeln();

    try {
      await file.writeAsString(buffer.toString(), mode: FileMode.append);
    } catch (e) {
      debugPrint('Failed to write backend activity log: $e');
    }
  }

  Future<List<String>> getBackendActivityLogLines({int maxLines = 2000}) async {
    return _readTailLines(
      _backendActivityLogFile,
      missingMessage: 'No backend activity recorded yet.',
      maxLines: maxLines,
    );
  }

  Future<void> clearLocalLogs() async {
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.delete();
    }
  }

  Future<List<String>> _readTailLines(
    File? file, {
    required String missingMessage,
    int maxBytes = 262144,
    int maxLines = 2000,
  }) async {
    if (file == null || !await file.exists()) {
      return <String>[missingMessage];
    }
    try {
      final length = await file.length();
      final start = length > maxBytes ? length - maxBytes : 0;
      final handle = await file.open();
      try {
        await handle.setPosition(start);
        final bytes = await handle.read(length - start);
        var text = utf8.decode(bytes, allowMalformed: true);
        if (start > 0) {
          final firstNewline = text.indexOf('\n');
          if (firstNewline >= 0 && firstNewline + 1 < text.length) {
            text = text.substring(firstNewline + 1);
          }
        }
        final lines = const LineSplitter().convert(text);
        if (lines.isEmpty) {
          return <String>[missingMessage];
        }
        if (lines.length <= maxLines) {
          return lines;
        }
        return lines.sublist(lines.length - maxLines);
      } finally {
        await handle.close();
      }
    } catch (e) {
      debugPrint('Failed to read log file: $e');
      return <String>['Failed to read logs: $e'];
    }
  }

  String _summarizePayload(String? payload, {int maxChars = 4000}) {
    if (payload == null) {
      return '';
    }
    final normalized = payload.trim();
    if (normalized.isEmpty) {
      return '';
    }
    if (normalized.length <= maxChars) {
      return normalized;
    }
    return '${normalized.substring(0, maxChars)}… [truncated]';
  }
}
