import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart'
    show ZetaIcons, ZetaListItem, ZetaSegmentedControl;
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart';
import 'package:neuro_toolkit/features/neurocnl/models/simulator_preflight.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/native_file_adapter_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/models/target_reachability.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/canvas/canvas_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/studio_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/pipeline_node_property_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/property_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_adapter.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../providers_test.mocks.dart';

/// Test double for gaps that need a *failing* file/workspace pick.
class _ThrowingNativeFileBackend implements NativeFileBackend {
  @override
  Future<List<OpenedTextFile>?> openTextFiles() =>
      throw Exception('not used in this test');

  @override
  Future<OpenedTextFile?> openWorkspaceFile() =>
      throw Exception('simulated open failure');

  @override
  Future<OpenedBinaryFile?> openDatasetImport() =>
      throw Exception('not used in this test');

  @override
  Future<SaveResult> saveTextFile({
    required String suggestedName,
    required String contents,
  }) => throw Exception('not used in this test');

  @override
  Future<SaveResult> saveWorkspaceFile({
    required String suggestedName,
    required String contents,
  }) => throw Exception('not used in this test');

  @override
  Future<SaveResult> saveBinaryFile({
    required String suggestedName,
    required Uint8List bytes,
    List<String>? allowedExtensions,
  }) => throw Exception('not used in this test');
}

/// Test double for the dataset-import busy-spinner test: hangs on whatever
/// [Future] the test supplies so the spinner can be observed mid-flight.
class _PendingImportNativeFileBackend implements NativeFileBackend {
  _PendingImportNativeFileBackend(this._pending);
  final Future<OpenedBinaryFile?> _pending;

  @override
  Future<OpenedBinaryFile?> openDatasetImport() => _pending;

  @override
  Future<List<OpenedTextFile>?> openTextFiles() =>
      throw Exception('not used in this test');

  @override
  Future<OpenedTextFile?> openWorkspaceFile() =>
      throw Exception('not used in this test');

  @override
  Future<SaveResult> saveTextFile({
    required String suggestedName,
    required String contents,
  }) => throw Exception('not used in this test');

  @override
  Future<SaveResult> saveWorkspaceFile({
    required String suggestedName,
    required String contents,
  }) => throw Exception('not used in this test');

  @override
  Future<SaveResult> saveBinaryFile({
    required String suggestedName,
    required Uint8List bytes,
    List<String>? allowedExtensions,
  }) => throw Exception('not used in this test');
}

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

  Future<void> pumpStudio(
    WidgetTester tester, {
    required Size size,
    String panel = 'parse',
    List<Override> extraOverrides = const [],
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
            WorkspaceBootstrap(initialLocation: '/?panel=$panel'),
          ),
          ...extraOverrides,
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StudioScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final restoreDialog = find.text('Restore previous session?');
    if (restoreDialog.evaluate().isNotEmpty) {
      await tester.tap(find.text('Start fresh'));
      await tester.pumpAndSettle();
    }
  }

  void seedCompletedResult(WidgetTester tester) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StudioScreen)),
    );
    container
        .read(studioResultSessionProvider.notifier)
        .restoreSnapshot(
          StudioResultSnapshot(
            id: 'responsive-source',
            completedAt: DateTime.utc(2026, 8, 10),
            provenance: const StudioResultProvenance(
              workspaceName: 'Responsive test',
              modelFingerprint: 'model-a',
            ),
            platforms: const <String, StudioPlatformResult>{
              'snntorch_sim': StudioPlatformResult(
                platform: 'snntorch_sim',
                outcome: StudioPlatformOutcome.complete,
                history: <TrainingEpochEvent>[
                  TrainingEpochEvent(epoch: 1, loss: 0.25),
                ],
              ),
            },
            selection: const StudioVisualizationSelection(),
            isPartial: false,
          ),
        );
  }

  group('StudioScreen Responsive Audit', () {
    for (final viewport in <(String, Size)>[
      ('tablet boundary', const Size(840, 900)),
      ('desktop', const Size(1440, 900)),
    ]) {
      testWidgets('floating controls stay separate on ${viewport.$1}', (
        WidgetTester tester,
      ) async {
        await pumpStudio(tester, size: viewport.$2);

        final workflow = find.byKey(const Key('studio-workflow-accordion'));
        final utility = find.byKey(const Key('studio-utility-pill'));
        expect(workflow, findsOneWidget);
        expect(utility, findsOneWidget);
        expect(find.byTooltip('Save workspace'), findsOneWidget);
        expect(find.byTooltip('All changes saved'), findsOneWidget);
        expect(find.text('Untitled Workspace'), findsOneWidget);

        final workflowRect = tester.getRect(workflow);
        final utilityRect = tester.getRect(utility);
        expect(workflowRect.right, lessThanOrEqualTo(utilityRect.left));
        expect(workflowRect.left, lessThan(utilityRect.left));
        if (viewport.$1 == 'desktop') {
          expect(workflowRect.width, lessThan(viewport.$2.width / 2));
          expect(workflowRect.width, greaterThan(300));
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Setup actions and canvas previews use the desktop split', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester, size: const Size(1440, 900));

      final workflowRect = tester.getRect(
        find.byKey(const Key('studio-workflow-accordion')),
      );
      final benchmarkRect = tester.getRect(find.text('Benchmark').first);
      final loadRect = tester.getRect(find.text('Load from hub'));
      // The load actions now sit on their own row directly below the
      // stepper rather than squeezed beside it, so they clear the stepper's
      // bottom edge and sit above the Setup step's own body content.
      expect(loadRect.top, greaterThanOrEqualTo(workflowRect.bottom));
      expect(benchmarkRect.top, greaterThanOrEqualTo(loadRect.bottom));
      expect(benchmarkRect.top - workflowRect.bottom, lessThanOrEqualTo(128));
      expect(find.text('Workspace preview'), findsOneWidget);
      expect(find.text('Model canvas'), findsOneWidget);
      expect(find.text('Training canvas'), findsOneWidget);
      expect(find.text('Evaluation canvas'), findsOneWidget);
      expect(find.text('0 nodes'), findsNWidgets(3));
      expect(find.text('0 edges'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone keeps its AppBar navigation without desktop floats', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester, size: const Size(390, 844));

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byTooltip('Save workspace'), findsOneWidget);
      expect(find.byKey(const Key('studio-workflow-accordion')), findsNothing);
      expect(find.byKey(const Key('studio-utility-pill')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // "Manage Targets" lives on the Setup step's selected-platform list (see
    // setup_step.dart's _buildSelectedPlatformsList), not on the deploy panel
    // — hardware target management moved there in the ponytail restructure.
    // That summary list is now shared between desktop and mobile
    // (setup_step.dart:27 only swaps the *entry point* — an inline dropdown
    // vs. a "Target platform" row + checkbox bottom sheet — below 840px; the
    // summary list itself, including "Manage Targets", is identical either
    // way). This test asserts the mobile summary row is visible and
    // in-viewport; see "Manage Targets is reachable on mobile" below for the
    // hardware-target affordance itself.
    testWidgets('Setup step - Target platform summary is visible at 390px', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester, size: const Size(390, 844));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(StudioScreen)),
      );
      container
          .read(workspaceProvider.notifier)
          .setActivePipelineStep('selectData');
      container.read(workspaceProvider.notifier).togglePlatform('akida');
      await tester.pumpAndSettle();

      // Check for overflows
      expect(tester.takeException(), isNull);

      // Verify the mobile "Target platform" summary row reflects the
      // selection and is within viewport.
      final rowFinder = find.text('1 selected');
      expect(rowFinder, findsOneWidget);

      final rowRect = tester.getRect(rowFinder);
      expect(rowRect.left, greaterThanOrEqualTo(0));
      expect(rowRect.right, lessThanOrEqualTo(390));
    });

    testWidgets('Setup step - Target platform sheet opens without overflow and '
        'checkboxes are tappable at 390px', (WidgetTester tester) async {
      await pumpStudio(tester, size: const Size(390, 844));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(StudioScreen)),
      );
      container
          .read(workspaceProvider.notifier)
          .setActivePipelineStep('selectData');
      await tester.pumpAndSettle();

      // Open the "Target platform" bottom sheet (regression check: this
      // used to overflow with an unbounded Column of checkboxes). Invoke
      // the row's onTap directly rather than a coordinate-based tap — the
      // row sits inside a scrollable ListView and hit-testing a specific
      // pixel is flaky under the test surface, while the callback itself
      // is exactly what a real tap invokes.
      final targetRow = tester.widget<ZetaListItem>(
        find.ancestor(
          of: find.text('Target platform'),
          matching: find.byType(ZetaListItem),
        ),
      );
      targetRow.onTap!();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The sheet must actually be open and scrollable/bounded now — this
      // is the regression this test guards against.
      expect(find.byType(Checkbox), findsWidgets);
      expect(find.text('Done'), findsOneWidget);

      // Tick a platform checkbox inside the sheet (same reasoning as
      // above: invoke the callback directly rather than a coordinate tap).
      tester.widget<Checkbox>(find.byType(Checkbox).first).onChanged!(true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Confirm via "Done" and verify the selection was applied.
      final doneButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Done'),
          matching: find.byType(FilledButton),
        ),
      );
      doneButton.onPressed!();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(container.read(workspaceProvider).selectedPlatforms, isNotEmpty);
    });

    testWidgets(
      'Setup step - Load from server is present on mobile and opens the '
      'picker without overflow',
      (WidgetTester tester) async {
        when(mockApi.listServerWorkspaces()).thenAnswer((_) async => const []);

        await pumpStudio(tester, size: const Size(390, 844));
        final container = ProviderScope.containerOf(
          tester.element(find.byType(StudioScreen)),
        );
        container
            .read(workspaceProvider.notifier)
            .setActivePipelineStep('selectData');
        await tester.pumpAndSettle();

        // Bug: "Load from server" — a fully-implemented flow — was
        // completely unreachable on mobile; only "Load Workspace" (device)
        // and "Load from Hub" existed.
        final serverRow = tester.widget<ZetaListItem>(
          find.ancestor(
            of: find.text('Load from server'),
            matching: find.byType(ZetaListItem),
          ),
        );
        serverRow.onTap!();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text('No workspaces have been saved on this server yet.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Setup step - workspace error banner surfaces on mobile and dismisses',
      (WidgetTester tester) async {
        // Bug: _workspaceError was set on failure but never rendered by the
        // mobile layout — load failures were silently swallowed.
        await pumpStudio(
          tester,
          size: const Size(390, 844),
          extraOverrides: [
            nativeFileAdapterProvider.overrideWithValue(
              FileAdapter(_ThrowingNativeFileBackend()),
            ),
          ],
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(StudioScreen)),
        );
        container
            .read(workspaceProvider.notifier)
            .setActivePipelineStep('selectData');
        await tester.pumpAndSettle();

        final loadRow = tester.widget<ZetaListItem>(
          find.ancestor(
            of: find.text('Load Workspace'),
            matching: find.byType(ZetaListItem),
          ),
        );
        loadRow.onTap!();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(MaterialBanner), findsOneWidget);
        expect(
          find.text('Workspace open failed. Check the file and try again.'),
          findsOneWidget,
        );

        // Invoke the Dismiss button's onPressed directly rather than a
        // coordinate-based tap — this row sits inside a scrollable ListView
        // and hit-testing a specific pixel is flaky under the test surface
        // (same reasoning as elsewhere in this file).
        final dismissButton = tester.widget<TextButton>(
          find.ancestor(
            of: find.text('Dismiss'),
            matching: find.byType(TextButton),
          ),
        );
        dismissButton.onPressed!();
        await tester.pumpAndSettle();
        expect(find.byType(MaterialBanner), findsNothing);
      },
    );

    testWidgets(
      'Setup step - Manage Targets, reachability dot, and quick-remove are '
      'reachable on mobile',
      (WidgetTester tester) async {
        when(mockApi.getTargetReachability(any)).thenAnswer(
          (_) async => const TargetReachability(
            reachable: true,
            detail: '1 device(s) found',
          ),
        );

        await pumpStudio(tester, size: const Size(390, 844));
        final container = ProviderScope.containerOf(
          tester.element(find.byType(StudioScreen)),
        );
        container
            .read(workspaceProvider.notifier)
            .setActivePipelineStep('selectData');
        container.read(workspaceProvider.notifier).togglePlatform('akida');
        await tester.pumpAndSettle();

        // Bug: the desktop-only _buildSelectedPlatformsList() was the only
        // place "Manage Targets" and the reachability dot rendered — mobile
        // had no equivalent at all.
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Manage Targets'), findsOneWidget);
        // Keyed rather than matched on tooltip text: Akida's dot reports the
        // paired remote host's readiness (via launcher control), so its message
        // depends on that host rather than on the backend container's own
        // `/targets/akida/reachability` probe. This assertion is about the dot
        // being present on mobile at all.
        expect(find.byKey(const Key('reachability-dot-akida')), findsOneWidget);

        final manageButton = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.settings_ethernet_outlined),
        );
        manageButton.onPressed!();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Some management surface opened — proves the callback actually
        // fired from mobile rather than being unreachable.
        expect(find.byType(Dialog), findsWidgets);
        Navigator.of(tester.element(find.byType(Dialog).first)).pop();
        await tester.pumpAndSettle();

        // Quick-remove: the close IconButton clears the target without
        // reopening the bulk checkbox sheet.
        final closeButton = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, ZetaIcons.close).last,
        );
        closeButton.onPressed!();
        await tester.pumpAndSettle();
        expect(container.read(workspaceProvider).selectedPlatforms, isEmpty);
      },
    );

    testWidgets('Setup step - dataset import shows a busy spinner on mobile', (
      WidgetTester tester,
    ) async {
      final pendingImport = Completer<OpenedBinaryFile?>();
      await pumpStudio(
        tester,
        size: const Size(390, 844),
        extraOverrides: [
          nativeFileAdapterProvider.overrideWithValue(
            FileAdapter(_PendingImportNativeFileBackend(pendingImport.future)),
          ),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StudioScreen)),
      );
      container
          .read(workspaceProvider.notifier)
          .setActivePipelineStep('selectData');
      await tester.pumpAndSettle();

      // Bug: the desktop "Load from disk" button showed a spinner while
      // _isImportingDataset was true; the mobile row gave no feedback at
      // all that an import was in progress.
      expect(find.byType(CircularProgressIndicator), findsNothing);

      final importRow = tester.widget<ZetaListItem>(
        find.ancestor(
          of: find.text('Import from device'),
          matching: find.byType(ZetaListItem),
        ),
      );
      importRow.onTap!();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      pendingImport.complete(null);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Deploy surface renders without overflow at 390px', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester, size: const Size(390, 844), panel: 'deploy');

      // Deploy is configuration only — its results live in the Review step.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StudioScreen)),
      );
      seedCompletedResult(tester);
      if (!container
          .read(workspaceProvider)
          .selectedPlatforms
          .contains('akida')) {
        container.read(workspaceProvider.notifier).togglePlatform('akida');
      }
      container
          .read(workspaceProvider.notifier)
          .setSelectedDeployTarget('akida');
      container
          .read(workspaceProvider.notifier)
          .setActivePipelineStep('deployHardware');
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('Grid'), findsNothing);
    });

    testWidgets(
      'compact Deploy page has no bottom action dock for any target — '
      'hardware targets open a Configure dialog instead',
      (WidgetTester tester) async {
        await pumpStudio(tester, size: const Size(390, 844), panel: 'deploy');
        final container = ProviderScope.containerOf(
          tester.element(find.byType(StudioScreen)),
        );
        final workspace = container.read(workspaceProvider.notifier);
        seedCompletedResult(tester);
        container
            .read(workspaceProvider.notifier)
            .setActivePipelineStep('deployHardware');

        // The combined hardware/simulator tables render every target at
        // once now, so there's no more "currently selected target" whose
        // page might or might not own the compact dock — none of them do.
        // Hardware targets require an explicit "Configure" tap (which opens
        // a dialog, detached from the page's `_MobileDeployActionScope`);
        // simulators have their own inline per-row Run button instead.
        for (final target in const <String>[
          'akida',
          'pynq',
          'lava',
          'snntorch_sim',
          'sc_neurocore_fpga',
          'brian2',
        ]) {
          if (!container
              .read(workspaceProvider)
              .selectedPlatforms
              .contains(target)) {
            workspace.togglePlatform(target);
          }
          workspace.setSelectedDeployTarget(target);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(tester.takeException(), isNull, reason: target);
          expect(
            find.byKey(const Key('mobile-deploy-action-dock')),
            findsNothing,
            reason: '$target has no top-level compact deploy action',
          );
        }
      },
    );

    for (final size in const <Size>[
      Size(320, 700),
      Size(430, 900),
      Size(600, 900),
    ]) {
      testWidgets("Akida's Configure dialog opens safely at ${size.width}px", (
        WidgetTester tester,
      ) async {
        await pumpStudio(tester, size: size, panel: 'deploy');
        final container = ProviderScope.containerOf(
          tester.element(find.byType(StudioScreen)),
        );
        if (!container
            .read(workspaceProvider)
            .selectedPlatforms
            .contains('akida')) {
          container.read(workspaceProvider.notifier).togglePlatform('akida');
        }
        container
            .read(workspaceProvider.notifier)
            .setActivePipelineStep('deployHardware');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // The hardware table's row-level dialog replaces the old compact
        // mobile action dock — Akida's setup page is only reachable
        // through it now, on every width. Fixed-duration pumps rather than
        // pumpAndSettle: a pre-existing rendering hiccup at 600px
        // (nmtk_ui_core/lib/widgets/snn_workflow_stepper.dart) keeps
        // scheduling frames forever at that width, so pumpAndSettle never
        // returns there.
        final openAkida = find.byKey(const Key('hardware-target-open-akida'));
        await tester.ensureVisible(openAkida);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(openAkida);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final dialog = find.byType(Dialog);
        expect(dialog, findsOneWidget);
        expect(tester.getRect(dialog).right, lessThanOrEqualTo(size.width));
      });
    }

    for (final textScale in const <double>[1, 1.5, 2]) {
      testWidgets(
        "Akida's Configure dialog wraps cleanly at ${textScale}x text scale",
        (WidgetTester tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pumpStudio(tester, size: const Size(390, 844), panel: 'deploy');
          final container = ProviderScope.containerOf(
            tester.element(find.byType(StudioScreen)),
          );
          if (!container
              .read(workspaceProvider)
              .selectedPlatforms
              .contains('akida')) {
            container.read(workspaceProvider.notifier).togglePlatform('akida');
          }
          container
              .read(workspaceProvider.notifier)
              .setActivePipelineStep('deployHardware');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          final openAkida = find.byKey(const Key('hardware-target-open-akida'));
          await tester.ensureVisible(openAkida);
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(openAkida);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(Dialog), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('Deploy surface renders without overflow at 840px', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester, size: const Size(840, 900), panel: 'deploy');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StudioScreen)),
      );
      seedCompletedResult(tester);
      container.read(workspaceProvider.notifier)
        ..togglePlatform('akida')
        ..setSelectedDeployTarget('akida');
      container
          .read(workspaceProvider.notifier)
          .setActivePipelineStep('deployHardware');
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('deploy-targets-overview')), findsOneWidget);
      expect(find.text('Grid'), findsNothing);

      // The same result surface must also fit in the Review step. Two pumps:
      // the stage area jumps pages in a post-frame callback.
      container
          .read(workspaceProvider.notifier)
          .setActivePipelineStep('deployReview');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('Architecture'), findsOneWidget);
      expect(find.text('Grid'), findsOneWidget);
      expect(find.text('Raster'), findsOneWidget);
      expect(find.text('Weights'), findsOneWidget);
    });

    testWidgets('Deploy surface renders without overflow on wide desktop', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester, size: const Size(1440, 900), panel: 'deploy');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StudioScreen)),
      );
      seedCompletedResult(tester);
      container.read(workspaceProvider.notifier)
        ..togglePlatform('akida')
        ..setSelectedDeployTarget('akida');
      container
          .read(workspaceProvider.notifier)
          .setActivePipelineStep('deployHardware');
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('deploy-targets-overview')), findsOneWidget);
      expect(find.text('Grid'), findsNothing);

      // The same result surface must also fit in the Review step. Two pumps:
      // the stage area jumps pages in a post-frame callback.
      container
          .read(workspaceProvider.notifier)
          .setActivePipelineStep('deployReview');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('Architecture'), findsOneWidget);
      expect(find.text('Grid'), findsOneWidget);
      expect(find.text('Raster'), findsOneWidget);
      expect(find.text('Weights'), findsOneWidget);
    });

    for (final viewport in <(String, Size)>[
      ('390px', const Size(390, 844)),
      ('840px', const Size(840, 900)),
      ('wide desktop', const Size(1440, 900)),
    ]) {
      testWidgets('completed Run stays on the live canvas at ${viewport.$1}', (
        WidgetTester tester,
      ) async {
        await pumpStudio(tester, size: viewport.$2);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(StudioScreen)),
        );
        container.read(workspaceProvider.notifier).setActivePipelineStep('run');
        seedCompletedResult(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(tester.takeException(), isNull);
        expect(container.read(workspaceProvider).activePipelineStep, 'run');
        for (final label in const [
          'Architecture',
          'Grid',
          'Raster',
          'Weights',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.byKey(const Key('run-result-view-switch')), findsOneWidget);
        expect(find.byKey(const Key('play-icon')), findsOneWidget);

        final viewSwitch = tester
            .widget<ZetaSegmentedControl<StudioResultView>>(
              find.descendant(
                of: find.byKey(const Key('run-result-view-switch')),
                matching: find.byType(ZetaSegmentedControl<StudioResultView>),
              ),
            );
        viewSwitch.onChanged!(StudioResultView.grid);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          find.byKey(const Key('studio-result-source-header')),
          findsNothing,
        );
        expect(find.text('Data'), findsNothing);
      });
    }

    testWidgets('Run view tabs sit between the desktop header controls', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester, size: const Size(1800, 900));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StudioScreen)),
      );
      container.read(workspaceProvider.notifier).setActivePipelineStep('run');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      final workflowRect = tester.getRect(
        find.byKey(const Key('studio-workflow-accordion')),
      );
      final viewSwitchRect = tester.getRect(
        find.byKey(const Key('run-result-view-switch')),
      );
      // The Architecture/Grid/Raster/Weights switch now always renders on
      // its own row directly below the stepper, rather than squeezed beside
      // it in the header — so it clears the stepper's bottom edge.
      expect(viewSwitchRect.top, greaterThanOrEqualTo(workflowRect.bottom));

      final viewSwitch = tester.widget<ZetaSegmentedControl<StudioResultView>>(
        find.descendant(
          of: find.byKey(const Key('run-result-view-switch')),
          matching: find.byType(ZetaSegmentedControl<StudioResultView>),
        ),
      );
      viewSwitch.onChanged!(StudioResultView.grid);
      await tester.pump();

      expect(
        tester.getTopLeft(find.byKey(const Key('run-noncanvas-content'))).dy,
        greaterThan(viewSwitchRect.bottom),
      );
    });

    testWidgets('Run step metrics move to a horizontal strip at 390px', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester, size: const Size(390, 844));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StudioScreen)),
      );
      container.read(workspaceProvider.notifier).setActivePipelineStep('run');
      await tester.pumpAndSettle();

      // No overflow at phone width — this is the regression the hardcoded
      // `Positioned(left: 264)` / fixed-width sidebar bugs in run_step.dart
      // used to cause.
      expect(tester.takeException(), isNull);

      // The vertical sidebar's header ("Live Metrics") only renders in the
      // desktop/tablet column layout — below the breakpoint, the metrics
      // move into a horizontal strip with no such header.
      expect(find.text('Live Metrics'), findsNothing);
      expect(
        find.byKey(const ValueKey('canvas-bottom-right-utility-dock')),
        findsNothing,
      );
    });

    testWidgets('Run step metrics dock bottom-right at 1200px', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester, size: const Size(1200, 900));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StudioScreen)),
      );
      container.read(workspaceProvider.notifier).setActivePipelineStep('run');
      // Bounded pumps rather than pumpAndSettle: the desktop split-pane
      // layout at this width keeps an indeterminate progress/animation loop
      // alive somewhere on screen, which pumpAndSettle never converges on.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(tester.takeException(), isNull);
      expect(find.text('Live Metrics'), findsOneWidget);

      final dock = find.byKey(
        const ValueKey('canvas-bottom-right-utility-dock'),
      );
      expect(dock, findsOneWidget);
      final dockRect = tester.getRect(dock);
      final canvasRect = tester.getRect(find.byType(CanvasScreen).last);
      expect(dockRect.right, closeTo(canvasRect.right - 12, 0.1));
      expect(dockRect.bottom, closeTo(canvasRect.bottom - 12, 0.1));
    });

    testWidgets('Model inspector docks in the bottom-right corner at 1200px', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockApi),
            workspaceBootstrapProvider.overrideWithValue(
              const WorkspaceBootstrap(initialLocation: '/?panel=model'),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: CanvasScreen(
                lockedTab: CanvasTab.architecture,
                initiallyShowInspector: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final inspector = find.byKey(const ValueKey('canvas-inspector-dock'));
      expect(inspector, findsOneWidget);
      final inspectorRect = tester.getRect(inspector);
      final canvasRect = tester.getRect(find.byType(CanvasScreen).last);
      expect(inspectorRect.right, closeTo(canvasRect.right - 12, 0.1));
      expect(inspectorRect.bottom, closeTo(canvasRect.bottom - 12, 0.1));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Deploy artifacts - Header metrics are scrollable and no overflow at 390px',
      (WidgetTester tester) async {
        await pumpStudio(tester, size: const Size(390, 844), panel: 'generate');
        final container = ProviderScope.containerOf(
          tester.element(find.byType(StudioScreen)),
        );
        container.read(workspaceProvider.notifier)
          ..togglePlatform('sc_neurocore_fpga')
          ..setActivePipelineStep('deployHardware');
        await tester.pumpAndSettle();

        final fpgaButton = find.byKey(
          const Key('hardware-target-open-sc_neurocore_fpga'),
        );
        await tester.ensureVisible(fpgaButton);
        await tester.pumpAndSettle();
        await tester.tap(fpgaButton);
        await tester.pumpAndSettle();

        final nirButton = find.text('View NIR Artifact');
        await tester.ensureVisible(nirButton);
        await tester.pumpAndSettle();
        await tester.tap(nirButton);
        await tester.pumpAndSettle();

        expect(find.text('Compiled Artifacts'), findsWidgets);
        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsWidgets);
      },
    );

    // The standalone validation panel/step no longer exists (ponytail
    // restructure flattened panels into the 7-step pipeline, none of which
    // is named "validation" — see kStudioPipelineStepNames). '?panel=
    // validation' now resolves to the defineModel step, which shows the
    // Canvas architecture editor with no "Validate" affordance anywhere.
    testWidgets(
      'Legacy validation panel deep link resolves without overflow at 390px',
      (WidgetTester tester) async {
        await pumpStudio(
          tester,
          size: const Size(390, 844),
          panel: 'validation',
        );

        // Check for overflows
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Legacy preview panel deep link resolves without overflow at 390px',
      (WidgetTester tester) async {
        await pumpStudio(
          tester,
          size: const Size(390, 844),
          panel: 'simulation',
        );

        // Check for overflows
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('mobile compact: shows only editor initially at 390px', (
      WidgetTester tester,
    ) async {
      await pumpStudio(tester, size: const Size(390, 844));

      expect(tester.takeException(), isNull);
      // Pipeline header (Run button area) should NOT be visible initially.
      expect(find.byKey(const Key('pipeline-panel-page-view')), findsNothing);
    });

    testWidgets(
      'selecting a node on mobile opens the inspector as a bottom sheet',
      (WidgetTester tester) async {
        // Mobile has no docked Inspector (see effectiveShowProperties in
        // canvas_screen.dart), so tapping a node must surface its params
        // some other way -- a modal sheet, asserted here directly via
        // selectNode() rather than a full canvas tap gesture, since the
        // sheet opens off the *selection* change, not the gesture itself.
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [apiClientProvider.overrideWithValue(mockApi)],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: CanvasScreen(lockedTab: CanvasTab.architecture),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PropertyPanel), findsNothing);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(CanvasScreen)),
        );
        container
            .read(canvasProvider.notifier)
            .setGraph(
              CanvasGraph(
                nodes: <CanvasNode>[
                  CanvasNode(
                    id: 'lif_1',
                    componentId: 'lif_population',
                    nirType: 'nir.LIF',
                    label: 'LIF',
                    parameters: const <String, dynamic>{'name': 'LIF 1'},
                    position: const <double>[400, 300],
                  ),
                ],
                edges: const <CanvasEdge>[],
                metadata: const <String, dynamic>{},
              ),
            );
        container.read(canvasProvider.notifier).selectNode('lif_1');
        await tester.pumpAndSettle();

        expect(
          find.byType(PropertyPanel),
          findsOneWidget,
          reason: 'selecting a node on mobile should open the sheet',
        );
        // PropertyPanel renders its own header (real node name + Delete +
        // Close) -- the sheet no longer adds a second, redundant header on
        // top of it, so this looks for the panel's own Delete affordance.
        expect(
          find.byTooltip('Delete node'),
          findsOneWidget,
          reason: 'the sheet must show exactly one Delete action, not two',
        );

        container.read(canvasProvider.notifier).clearSelection();
        await tester.pumpAndSettle();

        expect(
          find.byType(PropertyPanel),
          findsNothing,
          reason: 'clearing selection should dismiss the sheet',
        );
      },
    );

    testWidgets(
      'selecting a node only opens the sheet for the canvas it belongs to '
      '(regression: modal stacking across kept-alive tabs)',
      (WidgetTester tester) async {
        // In production, CanvasScreen is instantiated once per wizard step
        // (architecture, pipelineTrain, pipelineEval) and _KeepAliveWrapper
        // keeps every visited one mounted for the rest of the session, so
        // all of them share the single global canvasSelectedNodeIdProvider.
        // Selecting an architecture-only node must not also pop a sheet in
        // a still-mounted Train instance -- that's what compounded into a
        // near-black screen needing 3 dismisses.
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [apiClientProvider.overrideWithValue(mockApi)],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Column(
                  children: [
                    Expanded(
                      child: CanvasScreen(lockedTab: CanvasTab.architecture),
                    ),
                    Expanded(
                      child: CanvasScreen(lockedTab: CanvasTab.pipelineTrain),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(CanvasScreen).first),
        );
        container
            .read(canvasProvider.notifier)
            .setGraph(
              CanvasGraph(
                nodes: <CanvasNode>[
                  CanvasNode(
                    id: 'lif_1',
                    componentId: 'lif_population',
                    nirType: 'nir.LIF',
                    label: 'LIF',
                    parameters: const <String, dynamic>{'name': 'LIF 1'},
                    position: const <double>[400, 300],
                  ),
                ],
                edges: const <CanvasEdge>[],
                metadata: const <String, dynamic>{},
              ),
            );
        container.read(canvasProvider.notifier).selectNode('lif_1');
        await tester.pumpAndSettle();

        expect(
          find.byType(PropertyPanel),
          findsOneWidget,
          reason:
              'lif_1 belongs to the architecture graph, so only that '
              'canvas should open a sheet',
        );
        expect(
          find.byType(PipelineNodePropertyPanel),
          findsNothing,
          reason:
              'the Train canvas has no node with this id and must not '
              'open a sheet at all',
        );
      },
    );
  });
}
