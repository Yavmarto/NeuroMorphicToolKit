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

  test('AnalyticsService respect telemetry opt-in', () async {
    final analytics = AnalyticsService();
    analytics.telemetryEnabled = false;

    // This shouldn't throw or do much since it's disabled
    await analytics.trackEvent('test_event');

    analytics.telemetryEnabled = true;
    await analytics.trackEvent('test_event');
  });
}
