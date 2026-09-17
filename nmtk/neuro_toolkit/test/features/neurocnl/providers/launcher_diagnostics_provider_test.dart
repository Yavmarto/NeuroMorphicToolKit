import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/launcher_diagnostics.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/launcher_diagnostics_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';

void main() {
  test(
    'returns unavailable diagnostics when control plane fetch fails',
    () async {
      final api = _RecordingApiClient()
        ..launcherDiagnosticsError = Exception('control down');
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final diagnostics = await container.read(
        launcherDiagnosticsProvider.future,
      );

      expect(diagnostics.available, isFalse);
      expect(diagnostics.errorMessage, contains('control down'));
    },
  );

  test('returns launcher diagnostics from api client', () async {
    final api = _RecordingApiClient()
      ..launcherDiagnostics = const LauncherDiagnostics(
        available: true,
        suiteApiStatus: 'preflight_failed',
        suiteApiMessage: 'suite_api exited with code 1',
        logLines: <String>['[suite_api] crash line'],
      );
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final diagnostics = await container.read(
      launcherDiagnosticsProvider.future,
    );

    expect(diagnostics.available, isTrue);
    expect(diagnostics.suiteApiStatus, 'preflight_failed');
    expect(diagnostics.logLines, contains('[suite_api] crash line'));
  });
}

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient() : super(baseUrl: 'http://test');

  LauncherDiagnostics? launcherDiagnostics;
  Object? launcherDiagnosticsError;

  @override
  Future<LauncherDiagnostics> fetchLauncherDiagnostics() async {
    final error = launcherDiagnosticsError;
    if (error != null) {
      throw error;
    }
    return launcherDiagnostics!;
  }
}
