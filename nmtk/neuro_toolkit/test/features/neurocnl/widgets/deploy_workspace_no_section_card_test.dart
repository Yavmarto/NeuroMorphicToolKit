// Regression test for zeta-card-reduction Task 7: the Deploy panel + Akida
// workspace render WITHOUT NmtkSurfaceCard / NeurocnlSectionCard frames, use
// ZetaSegmentedControl for the deploy-target row and the AKIDA1/AKIDA2 +
// 1/2/4-bit selectors, and use NmtkStatusBanner for phase / inline-error
// surfaces (via the _StudioPhaseBanner / _StudioInlineError helpers).
//
// Validates: zeta-card-reduction Task 7 + the Zeta primitive map rules
// captured in `docs/current tasks/2026-05-26-zeta-card-reduction-handoff.md`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
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

  Future<void> pumpDeployPanel(
    WidgetTester tester, {
    String panelLocation = '/?panel=deploy&target=akida',
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          workspaceBootstrapProvider.overrideWithValue(
            WorkspaceBootstrap(initialLocation: panelLocation),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StudioScreen()),
        ),
      ),
    );
    // Two pumps let Zeta widgets settle without timing out the in-page
    // banner ripple (see handoff doc §3.2).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // Navigate straight to the Deploy step (step 7, 'deployHardware') —
    // it's no longer nested behind the Results step's training-history gate.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StudioScreen)),
    );
    container.read(workspaceProvider.notifier)
      ..togglePlatform('akida')
      ..setActivePipelineStep('deployHardware');
    await tester.pumpAndSettle();

    final restoreDialog = find.text('Restore previous session?');
    if (restoreDialog.evaluate().isNotEmpty) {
      await tester.tap(find.text('Start fresh'));
      await tester.pumpAndSettle();
    }

    final configure = find.byKey(const Key('hardware-target-open-akida'));
    if (configure.evaluate().isNotEmpty) {
      await tester.tap(configure);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('Akida workspace section uses NmtkSection', (
    WidgetTester tester,
  ) async {
    await pumpDeployPanel(tester);

    expect(
      find.byWidgetPredicate(
        (widget) => widget is NmtkSection && widget.title == 'Akida Runtime',
        description: 'NmtkSection(title: Akida Runtime)',
      ),
      findsOneWidget,
      reason:
          'Akida workspace must use NmtkSection '
          '(zeta-card-reduction Task 7). Re-introduction of the deleted '
          'NeurocnlSectionCard is enforced at source level by the T13 '
          'governance tests.',
    );
  });

  testWidgets(
    'Akida workspace renders zero NmtkSurfaceCard descendants (flat)',
    (WidgetTester tester) async {
      await pumpDeployPanel(tester);

      final akidaSectionFinder = find.byWidgetPredicate(
        (widget) => widget is NmtkSection && widget.title == 'Akida Runtime',
        description: 'NmtkSection(title: Akida Runtime)',
      );
      expect(akidaSectionFinder, findsOneWidget);

      expect(
        find.descendant(
          of: akidaSectionFinder,
          matching: find.byType(NmtkSurfaceCard),
        ),
        findsNothing,
      );
      // No legacy ChoiceChip rows inside the Akida workspace either — the
      // selectors are now ZetaSegmentedControl<String>/<int>.
      expect(
        find.descendant(
          of: akidaSectionFinder,
          matching: find.byType(ChoiceChip),
        ),
        findsNothing,
        reason:
            'Akida workspace selectors must be ZetaSegmentedControl, not '
            'ChoiceChip rows (zeta-card-reduction Task 7).',
      );
    },
  );

  testWidgets('Deploy panel renders 1 ZetaSegmentedControl<String> + 1 <int>', (
    WidgetTester tester,
  ) async {
    await pumpDeployPanel(tester);

    // One String segmented control: AKIDA1/AKIDA2 row.
    expect(
      find.byType(ZetaSegmentedControl<String>),
      findsOneWidget,
      reason:
          'Expected exactly one ZetaSegmentedControl<String> on the Akida '
          'deploy panel — the AKIDA1/AKIDA2 selector.',
    );

    // One int control: 1/2/4-bit weight quantization.
    expect(
      find.byType(ZetaSegmentedControl<int>),
      findsOneWidget,
      reason:
          'Expected exactly one ZetaSegmentedControl<int> for the bit-width '
          'selector on the Akida deploy panel (zeta-card-reduction Task 7).',
    );
  });

  testWidgets('Akida version + bit-width keyed segments are reachable', (
    WidgetTester tester,
  ) async {
    await pumpDeployPanel(tester);

    // AKIDA1 / AKIDA2.
    expect(find.byKey(const Key('akida-version-akida1')), findsOneWidget);
    expect(find.byKey(const Key('akida-version-akida2')), findsOneWidget);
    // 1 / 2 / 4-bit.
    expect(find.byKey(const Key('akida-bit-width-1')), findsOneWidget);
    expect(find.byKey(const Key('akida-bit-width-2')), findsOneWidget);
    expect(find.byKey(const Key('akida-bit-width-4')), findsOneWidget);
  });
}
