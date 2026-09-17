import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/feature_launch_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/studio_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

/// CEL-261 live golden-path gate — optional companion to the fast widget tests.
///
/// Exercises the real Studio Run UI against a live Suite API (same five combos
/// as `neuro ci golden-paths`). Skipped unless `NMTK_GOLDEN_PATHS_LIVE=1`.
///
///   NMTK_GOLDEN_PATHS_LIVE=1 \
///   NMTK_E2E_SERVER_HOST=203.0.113.90 \
///   flutter test integration_test/cel261_studio_golden_paths_e2e_test.dart -d macos
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final live = Platform.environment['NMTK_GOLDEN_PATHS_LIVE'] == '1';
  if (!live) {
    test('skipped — set NMTK_GOLDEN_PATHS_LIVE=1 for live Studio golden paths', () {});
    return;
  }

  final host = (Platform.environment['NMTK_E2E_SERVER_HOST']?.trim().isNotEmpty ?? false)
      ? Platform.environment['NMTK_E2E_SERVER_HOST']!.trim()
      : '203.0.113.90';
  final apiBase = 'http://$host:9000/api/neurocnl';

  Future<void> waitForOutcome(
    ProviderContainer container,
    String platformId,
    StudioPlatformOutcome expected, {
    int seconds = 300,
  }) async {
    for (var i = 0; i < seconds * 2; i++) {
      final outcome =
          container.read(studioResultSessionProvider).platforms[platformId]?.outcome;
      if (outcome == expected) return;
      if (outcome == StudioPlatformOutcome.error) {
        throw TestFailure('platform $platformId errored during golden path');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw TestFailure('timed out waiting for $platformId -> $expected');
  }

  Map<String, Object?> loadFixture(String fileName) {
    final path =
        '../../neurocli/neurocli/golden_paths/$fileName';
    return jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  }

  Future<ProviderContainer> pumpStudio(WidgetTester tester) async {
    await ServerConfigService.initialize();
    final launchContext = NmtkFeatureLaunchContext(
      moduleId: NmtkModuleId.neurocnl,
      backendUri: Uri.parse(apiBase),
      onNavigate: (_) async => false,
      onReportError: (_) async {},
      onEditServer: () async {},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          featureLaunchContextProvider.overrideWith(
            () => SeededFeatureLaunchContextNotifier(launchContext),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StudioScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(StudioScreen)));
  }

  testWidgets('nir+snntorch trains to completion on live backend', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = await pumpStudio(tester);
    container.read(workspaceProvider.notifier).replaceFromWorkspacePayload(
      loadFixture('nir_snntorch.nmtk'),
      sourceFileName: 'nir_snntorch.nmtk',
    );
    container.read(workspaceProvider.notifier).setActivePipelineStep('run');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('play-icon')));
    await tester.pump();

    await waitForOutcome(
      container,
      'snntorch_sim',
      StudioPlatformOutcome.complete,
    );
    expect(
      container.read(studioResultSessionProvider).phase,
      StudioResultSessionPhase.completed,
    );
  });
}
