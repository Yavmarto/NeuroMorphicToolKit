// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class MockPathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PathProviderPlatform.instance = MockPathProvider();
  });

  test('AnalyticsService logs crash locally', () async {
    final analytics = AnalyticsService();
    await analytics.init();
    await analytics.clearLocalLogs();

    final error = Exception('Test Exception');
    final stackTrace = StackTrace.current;

    await analytics.logCrash(error, stackTrace);

    final logs = await analytics.getLocalLogs();
    expect(logs, contains('FATAL ERROR: Exception: Test Exception'));
  });

  test('AnalyticsService redacts secrets in backend activity log', () async {
    final analytics = AnalyticsService();
    await analytics.init();
    await analytics.clearLocalLogs();

    await analytics.recordBackendActivity(
      method: 'POST',
      uri: Uri.parse('http://127.0.0.1:9000/api/launcher/deployment/bootstrap-remote-user'),
      statusCode: 200,
      requestBody:
          '{"host":"10.0.0.9","rootUsername":"root","rootPassword":"hunter2","rootPrivateKey":""}',
      responseBody:
          '{"username":"nmtk","sshPrivateKey":"-----BEGIN OPENSSH PRIVATE KEY-----\\nabc\\n-----END OPENSSH PRIVATE KEY-----\\n"}',
    );

    final lines = await analytics.getBackendActivityLogLines();
    final logText = lines.join('\n');

    expect(logText, isNot(contains('hunter2')));
    expect(logText, isNot(contains('BEGIN OPENSSH PRIVATE KEY')));
    expect(logText, contains('<redacted>'));
    // Non-sensitive fields must still be readable.
    expect(logText, contains('10.0.0.9'));
    expect(logText, contains('nmtk'));
  });

  test('AnalyticsService leaves non-JSON activity bodies untouched', () async {
    final analytics = AnalyticsService();
    await analytics.init();
    await analytics.clearLocalLogs();

    await analytics.recordBackendActivity(
      method: 'GET',
      uri: Uri.parse('http://127.0.0.1:9000/health'),
      statusCode: 200,
      requestBody: null,
      responseBody: 'plain text ok, not json',
    );

    final lines = await analytics.getBackendActivityLogLines();
    expect(lines.join('\n'), contains('plain text ok, not json'));
  });

  test('AnalyticsService respect telemetry opt-in', () async {
    final analytics = AnalyticsService();
    analytics.telemetryEnabled = false;

    // This shouldn't throw or do much since it's disabled
    await analytics.trackEvent('test_event');

    analytics.telemetryEnabled = true;
    await analytics.trackEvent('test_event');
  });
}
