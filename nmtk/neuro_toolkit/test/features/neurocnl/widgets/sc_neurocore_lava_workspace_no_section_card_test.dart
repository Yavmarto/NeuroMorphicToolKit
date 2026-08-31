// Regression test for zeta-card-reduction Task 8: the SC-NeuroCore (FPGA RTL)
// and Lava deploy workspaces are FLAT — no NmtkSurfaceCard frame, no
// ChoiceChip rows. Mirrors the structure of
// `deploy_workspace_no_section_card_test.dart` (Akida) and
// `pynq_deploy_no_nested_cards_test.dart` (PYNQ). Re-introduction of the
// deleted NeurocnlSectionCard is enforced at source level by the T13
// governance tests.

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

  Future<void> pumpDeployPanel(WidgetTester tester, String target) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          workspaceBootstrapProvider.overrideWithValue(
            WorkspaceBootstrap(
              initialLocation: '/?panel=deploy&target=$target',
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StudioScreen()),
        ),
      ),
    );
    // Two pumps let Zeta widgets settle without timing out the close-icon
    // ripple (see handoff doc §3.2).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // Navigate straight to the Deploy step (step 7, 'deployHardware') —
    // it's no longer nested behind the Results step's training-history gate.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StudioScreen)),
    );
    container.read(workspaceProvider.notifier)
      ..togglePlatform(target)
      ..setActivePipelineStep('deployHardware');
    await tester.pumpAndSettle();

    final restoreDialog = find.text('Restore previous session?');
    if (restoreDialog.evaluate().isNotEmpty) {
      await tester.tap(find.text('Start fresh'));
      await tester.pumpAndSettle();
    }

    final configure = find.byKey(Key('hardware-target-open-$target'));
    if (configure.evaluate().isNotEmpty) {
      await tester.tap(configure);
      await tester.pumpAndSettle();
    }
  }

  group('SC-NeuroCore FPGA RTL workspace (zeta-card-reduction Task 8)', () {
    testWidgets('uses NmtkSection', (WidgetTester tester) async {
      await pumpDeployPanel(tester, 'sc_neurocore_fpga');

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is NmtkSection && widget.title == 'SC-NeuroCore FPGA RTL',
          description: 'NmtkSection(title: SC-NeuroCore FPGA RTL)',
        ),
        findsOneWidget,
      );
    });

    testWidgets('has zero NmtkSurfaceCard descendants and no ChoiceChip rows', (
      WidgetTester tester,
    ) async {
      await pumpDeployPanel(tester, 'sc_neurocore_fpga');

      final sectionFinder = find.byWidgetPredicate(
        (widget) =>
            widget is NmtkSection && widget.title == 'SC-NeuroCore FPGA RTL',
        description: 'NmtkSection(title: SC-NeuroCore FPGA RTL)',
      );
      expect(sectionFinder, findsOneWidget);

      expect(
        find.descendant(
          of: sectionFinder,
          matching: find.byType(NmtkSurfaceCard),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: sectionFinder, matching: find.byType(ChoiceChip)),
        findsNothing,
        reason:
            'The FPGA RTL workspace must stay flat — no ChoiceChip '
            'rows (zeta-card-reduction Task 8).',
      );
    });

    testWidgets('shows synthesis target guidance and NIR artifact button', (
      WidgetTester tester,
    ) async {
      await pumpDeployPanel(tester, 'sc_neurocore_fpga');

      // "Manage Targets" for FPGA synthesis targets was consolidated into
      // Step 1 (Setup) — the deploy workspace itself only points the user
      // there via descriptive text, it no longer hosts its own button.
      expect(
        find.textContaining('Click "Manage Targets" to add an FPGA target.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ZetaButton, 'View NIR Artifact'),
        findsOneWidget,
      );
    });
  });

  group('Lava workspace (zeta-card-reduction Task 8)', () {
    testWidgets('uses NmtkSection', (WidgetTester tester) async {
      await pumpDeployPanel(tester, 'lava');

      expect(
        find.byWidgetPredicate(
          (widget) => widget is NmtkSection && widget.title == 'Lava Simulator',
          description: 'NmtkSection(title: Lava Simulator)',
        ),
        findsOneWidget,
      );
    });

    testWidgets('has zero NmtkSurfaceCard descendants and no ChoiceChip rows', (
      WidgetTester tester,
    ) async {
      await pumpDeployPanel(tester, 'lava');

      final sectionFinder = find.byWidgetPredicate(
        (widget) => widget is NmtkSection && widget.title == 'Lava Simulator',
        description: 'NmtkSection(title: Lava Simulator)',
      );
      expect(sectionFinder, findsOneWidget);

      expect(
        find.descendant(
          of: sectionFinder,
          matching: find.byType(NmtkSurfaceCard),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: sectionFinder, matching: find.byType(ChoiceChip)),
        findsNothing,
        reason:
            'Lava selectors (bit-width + run-config) must use '
            'ZetaSegmentedControl, not ChoiceChip rows '
            '(zeta-card-reduction Task 8).',
      );
    });

    testWidgets('uses the unauthenticated simulator panel by default', (
      WidgetTester tester,
    ) async {
      await pumpDeployPanel(tester, 'lava');

      expect(find.byKey(const Key('lava-simulator-panel')), findsOneWidget);
      expect(find.text('Prepare Loihi 2 hardware'), findsOneWidget);
      expect(find.byKey(const Key('lava-run-config-sim')), findsNothing);
      expect(find.byKey(const Key('lava-run-config-hw')), findsNothing);
    });

    testWidgets('only shows hardware deployment after the explicit action', (
      WidgetTester tester,
    ) async {
      await pumpDeployPanel(tester, 'lava');

      await tester.tap(find.text('Prepare Loihi 2 hardware'));
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is NmtkSection &&
              widget.title == 'Lava / Loihi 2 Hardware',
          description: 'NmtkSection(title: Lava / Loihi 2 Hardware)',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('lava-run-config-hw')), findsOneWidget);
    });
  });
}
