import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/simulator_preflight.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/studio_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/deploy/deploy_layout.dart';

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
    when(mockApi.preflight(any, any)).thenAnswer(
      (_) async => const PreflightResult(
        level: 'exact',
        supportedNodes: [],
        approximateNodes: [],
        unsupportedNodes: [],
        diagnostics: [],
      ),
    );
  });

  Future<void> pumpDeployTarget(
    WidgetTester tester, {
    required String target,
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(StudioScreen)),
    );
    container
        .read(workspaceProvider.notifier)
        .setActivePipelineStep('deployHardware');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isNotEmpty) {
      await tester.drag(scrollables.first, const Offset(0, -100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  group('Standard deploy layout parity across platforms', () {
    // Hardware targets no longer render their own page directly — the
    // Deploy step always shows the combined hardware-targets table, and a
    // target's `NmtkDeployLayout` page only mounts once its row's
    // "Configure" button opens it in a dialog.
    const hardwareTargets = <String>[
      'akida',
      'pynq',
      'lava',
      'sc_neurocore_fpga',
    ];

    for (final target in hardwareTargets) {
      testWidgets("$target's Configure dialog renders with NmtkDeployLayout", (
        WidgetTester tester,
      ) async {
        await pumpDeployTarget(tester, target: target);

        expect(find.byKey(const Key('hardware-targets-table')), findsOneWidget);
        expect(find.byType(NmtkDeployLayout), findsNothing);

        final openButton = find.byKey(Key('hardware-target-open-$target'));
        await tester.ensureVisible(openButton);
        await tester.pumpAndSettle();
        await tester.tap(openButton);
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(NmtkDeployLayout),
          ),
          findsOneWidget,
          reason: '$target deploy workspace must use NmtkDeployLayout',
        );
      });
    }

    // Codegen-only targets (brian2/sinabs/...) render the same way, but their
    // preview button only appears once Setup has selected that platform.
    const codegenTargets = <String>['brian2', 'sinabs'];

    for (final target in codegenTargets) {
      testWidgets("$target's code preview dialog opens", (
        WidgetTester tester,
      ) async {
        await pumpDeployTarget(tester, target: target);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(StudioScreen)),
        );
        if (!container
            .read(workspaceProvider)
            .selectedPlatforms
            .contains(target)) {
          container.read(workspaceProvider.notifier).togglePlatform(target);
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        final previewButton = find.byKey(Key('codegen-target-preview-$target'));
        await tester.ensureVisible(previewButton);
        await tester.pumpAndSettle();
        await tester.tap(previewButton);
        await tester.pumpAndSettle();

        // No spec is loaded in this minimal test harness, so the panel
        // shows its empty-state prompt (`_CodegenPreviewPanel`'s
        // `NmtkDeployLayout` branch only mounts once a network exists) —
        // this just asserts the dialog itself opens with that target's
        // panel inside, same as the hardware targets above.
        expect(find.byType(Dialog), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.textContaining('Architecture tab'),
          ),
          findsOneWidget,
          reason: '$target code preview dialog must show its own content',
        );
      });
    }

    const simulatorTargets = <String>[
      'snntorch_sim',
      'lava_sim',
      'sc_neurocore_sim',
    ];

    for (final target in simulatorTargets) {
      testWidgets(
        'picking $target opens the combined simulator targets table',
        (WidgetTester tester) async {
          await pumpDeployTarget(tester, target: target);

          expect(
            find.byKey(const Key('simulator-targets-table')),
            findsOneWidget,
          );
          expect(find.byType(NmtkDeployLayout), findsNothing);
          // All three simulator targets appear as rows regardless of which
          // one was picked from the deploy-target dropdown.
          for (final backend in simulatorTargets) {
            expect(
              find.byKey(Key('simulator-target-row-$backend')),
              findsOneWidget,
              reason: '$backend row missing when $target was selected',
            );
          }
        },
      );
    }

    testWidgets(
      'wide desktop renders side-by-side with inference on left and setup on right',
      (WidgetTester tester) async {
        await pumpDeployTarget(
          tester,
          target: 'akida',
          size: const Size(1440, 900),
        );
        final akidaOpenButton = find.byKey(
          const Key('hardware-target-open-akida'),
        );
        await tester.ensureVisible(akidaOpenButton);
        await tester.pumpAndSettle();
        await tester.tap(akidaOpenButton);
        await tester.pumpAndSettle();

        final deployLayoutFinder = find.byType(NmtkDeployLayout);
        expect(deployLayoutFinder, findsOneWidget);

        final rowFinder = find.descendant(
          of: deployLayoutFinder,
          matching: find.byType(Row),
        );
        expect(rowFinder, findsWidgets);

        final setupFinder = find.text('Deployment setup');
        expect(setupFinder, findsOneWidget);
      },
    );

    testWidgets(
      'NmtkDeployLayout compact mode stacks vertically with setup above inference',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: NmtkDeployLayout(
                title: 'Test Target',
                isCompact: true,
                inference: Text('Inference Pane Area'),
                setup: Text('Setup Pane Area'),
              ),
            ),
          ),
        );

        expect(find.text('Test Target'), findsOneWidget);
        expect(find.text('Setup Pane Area'), findsOneWidget);
        expect(find.text('Inference Pane Area'), findsOneWidget);

        final setupTop = tester.getTopLeft(find.text('Setup Pane Area')).dy;
        final inferenceTop = tester
            .getTopLeft(find.text('Inference Pane Area'))
            .dy;
        expect(setupTop, lessThan(inferenceTop));
      },
    );

    testWidgets(
      'NmtkDeployLayout wide mode places inference on the left and setup on the right',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1440,
                child: NmtkDeployLayout(
                  title: 'Test Target',
                  inference: Text('Inference Pane Area'),
                  setup: Text('Setup Pane Area'),
                ),
              ),
            ),
          ),
        );

        final inferenceLeft = tester
            .getTopLeft(find.text('Inference Pane Area'))
            .dx;
        final setupLeft = tester.getTopLeft(find.text('Setup Pane Area')).dx;
        expect(inferenceLeft, lessThan(setupLeft));
      },
    );
  });
}
