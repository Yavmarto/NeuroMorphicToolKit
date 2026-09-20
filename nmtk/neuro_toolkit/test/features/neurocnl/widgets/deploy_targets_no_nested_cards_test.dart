// Regression coverage for the Deploy step's target-picker removal: all
// deploy targets now render as rows in two combined tables (hardware +
// software simulators) instead of one page reached by picking a target from
// a dropdown. This file previously asserted the dropdown itself rendered
// flat (no NmtkSurfaceCard ancestor); now it asserts the dropdown is gone
// entirely and the combined tables take its place.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/studio_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

import '../providers_test.mocks.dart';

void main() {
  late MockApiClient mockApi;

  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
    mockApi = MockApiClient();
    when(mockApi.getTemplates()).thenAnswer((_) async => const []);
  });

  Future<void> pumpDeployPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          workspaceBootstrapProvider.overrideWithValue(
            const WorkspaceBootstrap(initialLocation: '/?panel=deploy'),
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

    // Navigate straight to the Deploy step (step 7, 'deployHardware') —
    // it's no longer nested behind the Results step's training-history gate.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StudioScreen)),
    );
    container
        .read(workspaceProvider.notifier)
        .setActivePipelineStep('deployHardware');
    await tester.pumpAndSettle();
  }

  testWidgets('Deploy step no longer renders a target-picker dropdown', (
    WidgetTester tester,
  ) async {
    await pumpDeployPanel(tester);

    expect(find.byKey(const Key('deploy-targets-dropdown')), findsNothing);
    expect(find.byKey(const Key('deploy-targets-single')), findsNothing);
    expect(find.byType(ZetaDropdown<String>), findsNothing);
    expect(find.text('Deploy to'), findsNothing);
  });

  testWidgets(
    'Deploy step renders the combined hardware and simulator tables',
    (WidgetTester tester) async {
      await pumpDeployPanel(tester);

      expect(find.byKey(const Key('deploy-targets-overview')), findsOneWidget);
      expect(find.byKey(const Key('hardware-targets-table')), findsOneWidget);
      expect(find.byKey(const Key('simulator-targets-table')), findsOneWidget);
      // Lava / Loihi2 gets its own mini table under the simulators section
      // (see `deploy_targets_overview.dart`) — it defaults to simulator mode,
      // so it isn't in the fixed hardware-targets table alongside Akida/PYNQ/
      // SC-NeuroCore FPGA. Hardware table + Lava's own table + simulator
      // table = 3 `DataTable`s in total.
      expect(find.byKey(const Key('lava-hardware-table')), findsOneWidget);
      expect(find.byKey(const Key('live-source-targets-table')), findsNothing);
      expect(find.byType(DataTable), findsNWidgets(3));

      for (final id in ['akida', 'pynq', 'lava', 'sc_neurocore_fpga']) {
        expect(
          find.byKey(Key('hardware-target-row-$id')),
          findsOneWidget,
          reason: 'Missing hardware target row for $id.',
        );
      }
      for (final id in [
        'lava_sim',
        'snntorch_sim',
        'sc_neurocore_sim',
        'brian2_sim',
        'sinabs_sim',
        'nengo_sim',
        'rockpool',
      ]) {
        expect(
          find.byKey(Key('simulator-target-row-$id')),
          findsOneWidget,
          reason: 'Missing runtime target row for $id.',
        );
      }
    },
  );

  testWidgets(
    'Opening a hardware target row shows its setup page in a dialog',
    (WidgetTester tester) async {
      await pumpDeployPanel(tester);

      final openAkida = find.byKey(const Key('hardware-target-open-akida'));
      await tester.ensureVisible(openAkida);
      await tester.pumpAndSettle();
      await tester.tap(openAkida);
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Akida'), findsWidgets);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    },
  );
}
