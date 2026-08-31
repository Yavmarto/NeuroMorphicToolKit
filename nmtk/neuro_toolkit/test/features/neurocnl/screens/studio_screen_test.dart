import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical_doc;
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart' as canvas_model;
import 'package:neuro_toolkit/features/neurocnl/models/network_graph.dart';
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/sc_neurocore_synthesis_target.dart';
import 'package:neuro_toolkit/features/neurocnl/models/simulation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/simulation_provider.dart'
    as canvas_sim;
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/native_file_adapter_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/running_notebook_tasks_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/server_config_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_akida_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_view_mode_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/canvas/canvas_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/studio_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart' as canvas_api;
import 'package:neuro_toolkit/features/neurocnl/services/file_adapter.dart';
import 'package:neuro_toolkit/features/neurocnl/services/sc_neurocore_target_service.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_target_registry_service.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/workspace_file.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/export_menu.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../providers_test.mocks.dart';

/// Drives the studio view-mode toggle from a widget test.
///
/// Zeta's [ZetaSegmentedControl] uses a custom render-object hit-test that
/// does not deliver `tester.tap(find.byKey(...))` to the inner segment label
/// reliably (zeta-card-reduction Task 4 — verified by extensive probing).
/// Tests that need to *change* the view mode therefore drive the
/// `studioViewModeProvider` directly via this helper. The
/// `find.byKey('cnl/nir/canvas-view-toggle')` finders still resolve and are
/// still used for visibility assertions.
Future<void> _setViewMode(WidgetTester tester, StudioViewMode mode) async {
  final element = tester.element(find.byType(StudioScreen));
  ProviderScope.containerOf(
    element,
  ).read(studioViewModeProvider.notifier).setMode(mode);
  await tester.pumpAndSettle();
}

/// Locates the editable text of a labelled Zeta form field.
///
/// Zeta renders the label as a sibling above the input rather than as an
/// [InputDecoration], so `find.widgetWithText` never matches — the label has to
/// be walked up to its [ZetaTextInput] and back down to the [EditableText].
Finder _studioFieldFor(String label) {
  return find.descendant(
    of: find.ancestor(
      of: find.text(label),
      matching: find.byType(ZetaTextInput),
    ),
    matching: find.byType(EditableText),
  );
}

/// Seeds a completed result session so Run renders its visualizer.
///
/// Split out from [_seedTrainingHistoryAndExpandDeploy]: the deploy panel now
/// lives on its own step (7, 'deployHardware'), so seeding history and
/// reaching the deploy panel are independent — tests that only need the
/// Results step populated should use this alone.
Future<void> _seedTrainingHistory(
  WidgetTester tester, {
  String platform = 'lava_sim',
}) async {
  final element = tester.element(find.byType(StudioScreen));
  final container = ProviderScope.containerOf(element);
  final session = container.read(studioResultSessionProvider.notifier);
  session.beginAttempt(
    platforms: [platform],
    provenance: const StudioResultProvenance(
      workspaceName: 'Test workspace',
      modelFingerprint: 'test-model',
    ),
  );
  session.recordEpoch(platform, const TrainingEpochEvent(epoch: 1, loss: 0.1));
  session.markComplete(platform);
  await tester.pumpAndSettle();
}

/// Seeds training history, then navigates to the Deploy step (step 7,
/// 'deployHardware').
///
/// The two are independent now that the deploy panel is its own step rather
/// than a modal opened from Results — this just keeps existing call sites
/// working. Use [_seedTrainingHistory] alone when the test needs to stay on
/// the Results step.
Future<void> _seedTrainingHistoryAndExpandDeploy(
  WidgetTester tester, {
  String platform = 'lava_sim',
}) async {
  await _seedTrainingHistory(tester, platform: platform);
  await _openDeployPanel(tester);
}

/// Navigates to the Deploy step (step 7, 'deployHardware'), which hosts the
/// hardware target picker, readiness/verdict, benchmark, and Hub sharing.
Future<void> _openDeployPanel(WidgetTester tester) async {
  final element = tester.element(find.byType(StudioScreen));
  final container = ProviderScope.containerOf(element);
  container
      .read(workspaceProvider.notifier)
      .setActivePipelineStep('deployHardware');
  await tester.pumpAndSettle();
}

/// Opens the "Manage Targets" dialog for [targetId].
///
/// After commit `41376fa8` ("remove Manage Targets (consolidated to Step
/// 1)"), the Manage Targets icon button only exists in the Setup step's
/// selected-platforms list, gated on the target being present in
/// `workspaceProvider`'s `selectedPlatforms` — a list distinct from
/// `selectedDeployTarget` that the `target=` bootstrap query param does not
/// populate. This helper adds the target to `selectedPlatforms`, switches to
/// the Setup step, taps the tooltip button there, and leaves the Manage
/// Targets dialog open.
Future<void> _openManageTargetsFor(WidgetTester tester, String targetId) async {
  final element = tester.element(find.byType(StudioScreen));
  final container = ProviderScope.containerOf(element);
  final notifier = container.read(workspaceProvider.notifier);
  if (!container.read(workspaceProvider).selectedPlatforms.contains(targetId)) {
    notifier.togglePlatform(targetId);
  }
  notifier.setActivePipelineStep('selectData');
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Manage Targets'));
  await tester.pumpAndSettle();
}

void main() {
  late MockApiClient mockApi;
  late _FakeStudioTargetRegistryService fakeTargetRegistry;
  late _FakeScNeuroCoreTargetService fakeScNeuroCoreService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    WebViewPlatform.instance = _FakeWebViewPlatform();
    // Reset the ServerConfigService singleton so the new mock initial values
    // take effect; without this, the cached SharedPreferences instance from a
    // previous test persists its in-memory state (e.g. the view mode written
    // by a test that tapped the canvas-view toggle).
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
    // Zero the workspace write/sync debounces. Both are bare Timers, which
    // schedule no frames — so pumpAndSettle returns with them still pending and
    // the binding fails the test with "A Timer is still pending even after the
    // widget tree was disposed" before any expect() is reached. The 1500ms
    // server sync in particular outlives every pump duration in this file,
    // which is what had ~18 tests here failing for reasons unrelated to what
    // they assert.
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    // Same class of problem, but a periodic timer: it is only cancelled in
    // ref.onDispose, which runs after the invariant check.
    RunningNotebookTasksNotifier.debugSetPollInterval(null);
    mockApi = MockApiClient();
    fakeTargetRegistry = _FakeStudioTargetRegistryService();
    fakeScNeuroCoreService = _FakeScNeuroCoreTargetService();
    when(mockApi.getTemplates()).thenAnswer((_) async => const []);
  });

  testWidgets(
    'Studio header places an injected action after the workspace name',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = _buildStudioContainer(
        mockApi: mockApi,
        backend: _RecordingNativeFileBackend(),
      );
      addTearDown(container.dispose);

      await _pumpStudio(
        tester,
        container,
        workspaceHeaderAction: const SizedBox(
          key: ValueKey<String>('host-workspace-header-action'),
          width: 24,
          height: 24,
        ),
      );

      final workspaceName = find.text('Untitled Workspace');
      final headerAction = find.byKey(
        const ValueKey<String>('host-workspace-header-action'),
      );
      expect(workspaceName, findsOneWidget);
      expect(headerAction, findsOneWidget);
      expect(
        tester.getTopLeft(headerAction).dx,
        greaterThan(tester.getTopRight(workspaceName).dx),
      );
    },
  );

  testWidgets('StudioScreen deploy panel shows compiled artifacts workspace', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          workspaceBootstrapProvider.overrideWithValue(
            const WorkspaceBootstrap(initialLocation: '/?panel=generate'),
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
    await _seedTrainingHistoryAndExpandDeploy(tester);

    // "View NIR Artifact" lives inside the SC-NeuroCore FPGA workspace page,
    // which the redesigned Deploy step no longer auto-renders — open its
    // dialog via the hardware table's Configure button first.
    await tester.tap(
      find.byKey(const Key('hardware-target-open-sc_neurocore_fpga')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View NIR Artifact'));
    await tester.pumpAndSettle();

    expect(find.text('Compiled Artifacts'), findsWidgets);
    expect(find.text('roundtrip.cnl'), findsOneWidget);
    expect(
      find.text('Run the model to see\nround-trip CNL output.'),
      findsOneWidget,
    );
  });

  testWidgets(
    "deploy panel's hardware table only lists targets Setup selected",
    (WidgetTester tester) async {
      // The dropdown-based picker used to mirror Setup's ticked platforms —
      // the table replacing it keeps that same rule: Setup owns platform
      // selection, Deploy only shows what was ticked there.
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockApi),
            studioTargetRegistryServiceProvider.overrideWithValue(
              fakeTargetRegistry,
            ),
            scNeuroCoreTargetServiceProvider.overrideWithValue(
              fakeScNeuroCoreService,
            ),
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

      final container = ProviderScope.containerOf(
        tester.element(find.byType(StudioScreen)),
      );
      final notifier = container.read(workspaceProvider.notifier);
      // Only two of the four hardware ids are ticked in Setup, on purpose:
      // the table must list exactly those two, not all four.
      for (final id in ['akida', 'pynq']) {
        if (!container.read(workspaceProvider).selectedPlatforms.contains(id)) {
          notifier.togglePlatform(id);
        }
      }
      await tester.pumpAndSettle();
      await _seedTrainingHistoryAndExpandDeploy(tester);

      expect(find.byKey(const Key('deploy-targets-dropdown')), findsNothing);
      expect(find.text('Deploy to'), findsNothing);
      expect(find.byKey(const Key('hardware-targets-table')), findsOneWidget);
      // `DataRow.key` (the `hardware-target-row-<id>` keys) is only used by
      // `Table`'s internal row-diffing bookkeeping — `DataRow` is a plain data
      // descriptor, not a `Widget`, so that key never reaches an `Element` and
      // `find.byKey` cannot see it. Each row's real, queryable identity is its
      // "Configure" button, keyed `hardware-target-open-<id>`.
      for (final id in ['akida', 'pynq']) {
        expect(
          find.byKey(Key('hardware-target-open-$id')),
          findsOneWidget,
          reason: '$id was ticked in Setup, so it must be listed',
        );
      }
      for (final id in ['lava', 'sc_neurocore_fpga']) {
        expect(
          find.byKey(Key('hardware-target-open-$id')),
          findsNothing,
          reason: '$id was never ticked in Setup, so it must not be listed',
        );
      }
    },
  );

  testWidgets(
    'StudioScreen deploy panel falls back to showing every target when '
    'Setup has nothing ticked yet',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockApi),
            studioTargetRegistryServiceProvider.overrideWithValue(
              fakeTargetRegistry,
            ),
            scNeuroCoreTargetServiceProvider.overrideWithValue(
              fakeScNeuroCoreService,
            ),
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
      await _seedTrainingHistoryAndExpandDeploy(tester);

      expect(find.text('Deploy to'), findsNothing);
      expect(find.byKey(const Key('deploy-targets-dropdown')), findsNothing);
      expect(find.text('SC-NeuroCore (FPGA RTL)'), findsOneWidget);
      // Setup's step gate normally prevents reaching Deploy with nothing
      // ticked, but a persisted/edge-case workspace still could — showing
      // everything is strictly better than showing two permanently-empty
      // tables ("Lava (Simulator)" is the simulator entry, "Lava / Loihi2"
      // the hardware one).
      expect(find.text('Lava (Simulator)'), findsWidgets);
      // Two, not one: the "Lava / Loihi2" sub-heading above the hardware
      // table (deploy_targets_overview.dart) and that table's own Target
      // cell both render the same label by design.
      expect(find.text('Lava / Loihi2'), findsWidgets);
      expect(find.text('Choose Deployment Target'), findsNothing);
      expect(find.text('Continue From Studio'), findsNothing);
      expect(find.text('Target-Specific Review'), findsNothing);
    },
  );

  testWidgets('StudioScreen deploy target popup filters to the chosen type', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          studioTargetRegistryServiceProvider.overrideWithValue(
            fakeTargetRegistry,
          ),
          workspaceBootstrapProvider.overrideWithValue(
            // Start the deploy panel with PYNQ pre-selected. After
            // zeta-card-reduction Task 7 the deploy-target row is a
            // ZetaSegmentedControl whose hit testing does not deliver
            // tester.tap(find.text(...)) reliably; the bootstrap URL is the
            // canonical way to pre-pick the target in tests.
            const WorkspaceBootstrap(
              initialLocation: '/?panel=deploy&target=akida',
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
    await tester.pumpAndSettle();
    await _seedTrainingHistory(tester);
    await _openManageTargetsFor(tester, 'akida');

    expect(find.text('Manage Akida targets'), findsOneWidget);
    expect(find.text('Saved targets'), findsOneWidget);
    expect(find.text('Add new target'), findsOneWidget);
    expect(find.text('Akida Host A'), findsOneWidget);
    expect(find.text('akida-linux.local • Ready'), findsOneWidget);
  });

  testWidgets('StudioScreen deploy target popup shows type-specific add form', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          studioTargetRegistryServiceProvider.overrideWithValue(
            fakeTargetRegistry,
          ),
          workspaceBootstrapProvider.overrideWithValue(
            // Pre-select PYNQ via bootstrap URL — see comment above.
            const WorkspaceBootstrap(
              initialLocation: '/?panel=deploy&target=akida',
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
    await tester.pumpAndSettle();
    await _seedTrainingHistory(tester);
    await _openManageTargetsFor(tester, 'akida');
    await tester.tap(find.text('Add new target'));
    await tester.pumpAndSettle();

    expect(find.text('Add Akida target'), findsOneWidget);
    expect(find.text('Host address'), findsOneWidget);
    expect(find.text('SSH port'), findsOneWidget);
    expect(find.text('SSH user'), findsOneWidget);
    expect(find.text('SSH password'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('StudioScreen Akida add form takes SSH user keystrokes', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          studioTargetRegistryServiceProvider.overrideWithValue(
            fakeTargetRegistry,
          ),
          workspaceBootstrapProvider.overrideWithValue(
            const WorkspaceBootstrap(
              initialLocation: '/?panel=deploy&target=akida',
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
    await tester.pumpAndSettle();
    await _seedTrainingHistory(tester);
    await _openManageTargetsFor(tester, 'akida');
    await tester.tap(find.text('Add new target'));
    await tester.pumpAndSettle();

    // Typing the host, then the SSH user, is the exact order a user follows.
    // Both fields have a listener attached, and both must survive a keystroke
    // without a setState()-during-build crash.
    await tester.enterText(_studioFieldFor('Host address'), '10.0.0.9');
    await tester.pumpAndSettle();
    await tester.enterText(_studioFieldFor('SSH user'), 'moosebun2');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('moosebun2'), findsOneWidget);

    // The service-account warning has to appear as the user types, not on save.
    await tester.enterText(_studioFieldFor('SSH user'), 'neurochip');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('akida-service-account-as-ssh-user-warning')),
      findsOneWidget,
    );
  });

  group('same-machine detection on the Akida add form', () {
    /// Pumps the Akida form with the app pointed at [backendUrl].
    ///
    /// The backend address is injected through the provider rather than
    /// SharedPreferences: seeding a real `serverUrl` makes dependent providers
    /// start work that never settles, so `pumpAndSettle` hangs.
    Future<void> pumpAkidaForm(
      WidgetTester tester, {
      required String backendUrl,
      bool openAddForm = true,
    }) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockApi),
            serverConfigProvider.overrideWithValue(
              ServerConfigState(serverUrl: backendUrl),
            ),
            studioTargetRegistryServiceProvider.overrideWithValue(
              fakeTargetRegistry,
            ),
            workspaceBootstrapProvider.overrideWithValue(
              const WorkspaceBootstrap(
                initialLocation: '/?panel=deploy&target=akida',
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
      await tester.pumpAndSettle();
      await _seedTrainingHistory(tester);
      await _openManageTargetsFor(tester, 'akida');
      await tester.tap(
        openAddForm
            ? find.text('Add new target')
            : find.byTooltip('Edit target'),
      );
      await tester.pumpAndSettle();
    }

    bool sameHostChecked(WidgetTester tester) {
      return tester
              .widget<CheckboxListTile>(
                find.byKey(const Key('akida-same-host-as-backend-checkbox')),
              )
              .value ??
          false;
    }

    testWidgets('ticks itself when the address is the backend server', (
      WidgetTester tester,
    ) async {
      // A card in the machine that already runs the backend must be reached
      // through the container gateway, not over the network. An end user has
      // no way to know that, so leaving it to a checkbox they must find and
      // understand is how this silently failed.
      await pumpAkidaForm(tester, backendUrl: 'http://backend.invalid:9000');
      expect(sameHostChecked(tester), isFalse);

      await tester.enterText(
        _studioFieldFor('Host address'),
        'backend.invalid',
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(sameHostChecked(tester), isTrue);
      expect(find.textContaining('Detected automatically'), findsOneWidget);
    });

    testWidgets('stays unticked for a genuinely separate machine', (
      WidgetTester tester,
    ) async {
      await pumpAkidaForm(tester, backendUrl: 'http://backend.invalid:9000');

      await tester.enterText(_studioFieldFor('Host address'), '10.0.0.9');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(sameHostChecked(tester), isFalse);
    });

    testWidgets('an explicit untick is not undone by further typing', (
      WidgetTester tester,
    ) async {
      await pumpAkidaForm(tester, backendUrl: 'http://backend.invalid:9000');

      await tester.enterText(
        _studioFieldFor('Host address'),
        'backend.invalid',
      );
      await tester.pumpAndSettle();
      expect(sameHostChecked(tester), isTrue);

      await tester.tap(
        find.byKey(const Key('akida-same-host-as-backend-checkbox')),
      );
      await tester.pumpAndSettle();
      expect(sameHostChecked(tester), isFalse);

      // Editing another field re-runs the host listener; detection must not
      // re-tick what the user just switched off.
      await tester.enterText(_studioFieldFor('SSH user'), 'moosebun2');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(sameHostChecked(tester), isFalse);
    });

    testWidgets('editing a saved target keeps its stored answer', (
      WidgetTester tester,
    ) async {
      // The fake host is 'akida-linux.local' with sameHostAsBackend false. Even
      // though that address IS the backend here, a stored record already
      // carries the user's decision and must outrank detection.
      await pumpAkidaForm(
        tester,
        backendUrl: 'http://akida-linux.local:9000',
        openAddForm: false,
      );

      expect(tester.takeException(), isNull);
      expect(sameHostChecked(tester), isFalse);
    });
  });

  testWidgets('StudioScreen deploy panel restores selected deploy target', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          studioTargetRegistryServiceProvider.overrideWithValue(
            fakeTargetRegistry,
          ),
          workspaceBootstrapProvider.overrideWithValue(
            const WorkspaceBootstrap(
              initialLocation: '/?panel=deploy&target=akida',
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
    await tester.pumpAndSettle();
    await _seedTrainingHistoryAndExpandDeploy(tester);

    expect(find.text('Akida'), findsWidgets);
    expect(
      ProviderScope.containerOf(
        tester.element(find.byType(StudioScreen)),
      ).read(workspaceProvider).selectedDeployTarget,
      'akida',
    );
  });

  testWidgets(
    'StudioScreen Akida readiness binds the selected host before running',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      _RecordingStudioAkidaDeployController? provider;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockApi),
            studioTargetRegistryServiceProvider.overrideWithValue(
              fakeTargetRegistry,
            ),
            // A fresh Notifier per creation — Riverpod rejects reusing one
            // instance across provider elements, and the deploy panel now
            // mounts in a dialog route rather than staying inline, so the
            // provider can legitimately be built more than once. `provider`
            // tracks the most recent instance, which is the one the panel under
            // test is bound to.
            studioAkidaDeployControllerProvider.overrideWith(() {
              provider = _RecordingStudioAkidaDeployController();
              return provider!;
            }),
            workspaceBootstrapProvider.overrideWithValue(
              const WorkspaceBootstrap(
                initialLocation: '/?panel=deploy&target=akida',
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
      await tester.pumpAndSettle();
      // Seed only — the deploy panel is a modal dialog now, and its barrier
      // would block the Manage Targets tap below.
      await _seedTrainingHistory(tester);
      await _openManageTargetsFor(tester, 'akida');
      await tester.tap(find.text('Akida Host A'));
      await tester.pumpAndSettle();
      expect(fakeTargetRegistry.lastSelectedAkidaHostId, 'akida-1');

      // Manage Targets lives on the Setup step; readiness is back on
      // the Deploy step's Akida workspace — navigate back, then open its
      // dialog via the hardware table's Configure button (selecting a saved
      // target closed the Manage Targets dialog above, and the Akida
      // workspace's automatic-preparation logic only runs once that page is
      // actually built, which now requires opening its dialog explicitly).
      final element2 = tester.element(find.byType(StudioScreen));
      ProviderScope.containerOf(element2)
          .read(workspaceProvider.notifier)
          .setActivePipelineStep('deployHardware');
      await tester.pumpAndSettle();
      await _openDeployPanel(tester);
      await tester.tap(find.byKey(const Key('hardware-target-open-akida')));
      await tester.pumpAndSettle();

      // Selecting the host now triggers readiness automatically.
      expect(provider!.lastSelectedHostId, 'akida-1');
      expect(provider!.checkReadinessCalls, 1);
      expect(provider!.discoverLatestBundleCalls, 1);
    },
  );

  testWidgets('StudioScreen masks saved Akida password when editing target', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          studioTargetRegistryServiceProvider.overrideWithValue(
            fakeTargetRegistry,
          ),
          workspaceBootstrapProvider.overrideWithValue(
            const WorkspaceBootstrap(
              initialLocation: '/?panel=deploy&target=akida',
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
    await tester.pumpAndSettle();
    await _seedTrainingHistory(tester);
    await _openManageTargetsFor(tester, 'akida');
    await tester.tap(find.byTooltip('Edit target'));
    await tester.pumpAndSettle();

    final passwordField = tester.widget<ZetaTextInput>(
      find.widgetWithText(ZetaTextInput, 'SSH password'),
    );
    expect(passwordField.controller?.text, '********');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // `null`, not `''`: the three password intents are now distinct, because
    // conflating "unchanged" with "cleared" meant a saved password could never
    // be removed. `null` omits the key so the backend keeps what it has; `''`
    // clears it.
    expect(fakeTargetRegistry.lastSavedAkidaPassword, isNull);
  });

  /// Pumps StudioScreen with the fake registry and opens Manage Targets for
  /// Akida. Shared by the connectivity-test cases below.
  Future<void> pumpManageAkidaTargets(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          studioTargetRegistryServiceProvider.overrideWithValue(
            fakeTargetRegistry,
          ),
          workspaceBootstrapProvider.overrideWithValue(
            const WorkspaceBootstrap(
              initialLocation: '/?panel=deploy&target=akida',
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
    await tester.pumpAndSettle();
    await _seedTrainingHistory(tester);
    await _openManageTargetsFor(tester, 'akida');
  }

  testWidgets('Akida target tile can test the connection and shows the verdict', (
    WidgetTester tester,
  ) async {
    // The connectivity-test route existed on launcher control with no Dart
    // caller at all, so a paired host could not be verified from anywhere in the
    // UI. On the SSH path it needs no API token, which makes it the right check
    // to offer next to the credentials.
    await pumpManageAkidaTargets(tester);

    await tester.tap(find.byKey(const Key('hardware-target-test-akida-1')));
    await tester.pumpAndSettle();

    expect(fakeTargetRegistry.connectivityTestedHostIds, ['akida-1']);
    expect(fakeTargetRegistry.provisionedHostIds, ['akida-1']);
    expect(
      find.byKey(const Key('hardware-target-list-status')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Runtime installed and running'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a failed connectivity test reports the reason and stays usable',
    (WidgetTester tester) async {
      fakeTargetRegistry.connectivityTestError = Exception('ssh: auth failed');
      await pumpManageAkidaTargets(tester);

      await tester.tap(find.byKey(const Key('hardware-target-test-akida-1')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('ssh: auth failed'), findsWidgets);
      // Still interactive — a failed test must not wedge the dialog.
      expect(
        find.byKey(const Key('hardware-target-test-akida-1')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Save and test connection saves first, then tests the saved host',
    (WidgetTester tester) async {
      await pumpManageAkidaTargets(tester);
      await tester.tap(find.byTooltip('Edit target'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('hardware-target-save-and-test')));
      await tester.pumpAndSettle();

      // Saved (the masked password left alone, so nothing overwritten) and then
      // tested against the id the save returned.
      expect(fakeTargetRegistry.lastSavedAkidaPassword, isNull);
      expect(fakeTargetRegistry.connectivityTestedHostIds, ['akida-1']);
      expect(fakeTargetRegistry.provisionedHostIds, ['akida-1']);
      expect(
        find.byKey(const Key('hardware-target-form-status')),
        findsOneWidget,
      );
    },
  );

  testWidgets('checking "same machine as backend" passes it through on save', (
    WidgetTester tester,
  ) async {
    // Saving an Akida host on the same box as the backend needs a distinct
    // SSH route (launcher-control can't dial its own host's LAN IP), so this
    // flag has to make it all the way from the checkbox to the save payload.
    await pumpManageAkidaTargets(tester);
    await tester.tap(find.byTooltip('Edit target'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('akida-same-host-as-backend-checkbox')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fakeTargetRegistry.lastSavedSameHostAsBackend, isTrue);
  });

  testWidgets('a save that cannot select the target leaves the form usable', (
    WidgetTester tester,
  ) async {
    // _selectHardwareDevice returning false used to leave _isSaving stuck true
    // forever, so a save that had already committed looked like a failure and
    // users retyped their password and tried again.
    fakeTargetRegistry.selectAkidaHostError = Exception(
      'launcher control down',
    );
    await pumpManageAkidaTargets(tester);
    await tester.tap(find.byTooltip('Edit target'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Button is back to 'Save', not stuck on 'Saving...'.
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Saving...'), findsNothing);
  });

  /// Pumps StudioScreen with the fake registry and opens Manage Targets for
  /// PYNQ. Counterpart to [pumpManageAkidaTargets].
  Future<void> pumpManagePynqTargets(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          studioTargetRegistryServiceProvider.overrideWithValue(
            fakeTargetRegistry,
          ),
          workspaceBootstrapProvider.overrideWithValue(
            const WorkspaceBootstrap(
              initialLocation: '/?panel=deploy&target=pynq',
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
    await tester.pumpAndSettle();
    await _seedTrainingHistory(tester);
    await _openManageTargetsFor(tester, 'pynq');
  }

  testWidgets('a PYNQ board can be paired from Manage Targets', (
    WidgetTester tester,
  ) async {
    // The launcher's board CRUD routes and the registry methods for them both
    // existed with no caller at all, so a PYNQ board could not be paired from
    // anywhere in the app — the target was verdict-only.
    await pumpManagePynqTargets(tester);

    expect(find.text('PYNQ Z2 Dev Board'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit target'));
    await tester.pumpAndSettle();

    // The PYNQ form is its own branch, not the display-name-only fallback the
    // default case renders.
    expect(
      find.byKey(const Key('pynq-advanced-settings-toggle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('pynq-default-target-checkbox')),
      findsOneWidget,
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Saved, and the selection persisted to launcher control — which is what
    // its preflight and deploy proxies act on.
    expect(fakeTargetRegistry.lastSelectedPynqBoardId, 'pynq-1');
  });

  testWidgets('editing a saved PYNQ board leaves its stored password alone', (
    WidgetTester tester,
  ) async {
    // Same trap as Akida's: the masked placeholder must not be submitted as a
    // literal password, or opening the dialog silently overwrites the secret.
    await pumpManagePynqTargets(tester);
    await tester.tap(find.byTooltip('Edit target'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fakeTargetRegistry.lastSavedPynqPassword, isEmpty);
  });

  testWidgets('a PYNQ save that cannot select the board stays usable', (
    WidgetTester tester,
  ) async {
    fakeTargetRegistry.selectPynqBoardError = Exception(
      'launcher control down',
    );
    await pumpManagePynqTargets(tester);
    await tester.tap(find.byTooltip('Edit target'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Saving...'), findsNothing);
  });

  testWidgets('a PYNQ board offers Save and test connection', (
    WidgetTester tester,
  ) async {
    // Both this button and the per-row Test icon read one callback, and
    // `onTestTarget` used to be passed only for akida — so a PYNQ board could be
    // saved but never contacted, and its status dot stayed grey with nothing in
    // the app able to move it.
    await pumpManagePynqTargets(tester);
    await tester.tap(find.byTooltip('Edit target'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('hardware-target-save-and-test')));
    await tester.pumpAndSettle();

    // Saved first — the test route is keyed by board id, which a board being
    // created does not have yet — then tested against the id the save returned.
    expect(fakeTargetRegistry.lastSelectedPynqBoardId, 'pynq-1');
    expect(fakeTargetRegistry.connectivityTestedPynqBoardIds, ['pynq-1']);
    expect(
      find.byKey(const Key('hardware-target-form-status')),
      findsOneWidget,
    );
    // No provision follows: SSH `python3 --version` answers before the board
    // agent exists, and a cold provision needs 90–100 s.
    expect(fakeTargetRegistry.provisionedPynqBoardIds, isEmpty);
  });

  testWidgets('a PYNQ target tile can test the connection', (
    WidgetTester tester,
  ) async {
    await pumpManagePynqTargets(tester);

    await tester.tap(find.byKey(const Key('hardware-target-test-pynq-1')));
    await tester.pumpAndSettle();

    expect(fakeTargetRegistry.connectivityTestedPynqBoardIds, ['pynq-1']);
    expect(
      find.byKey(const Key('hardware-target-list-status')),
      findsOneWidget,
    );
  });

  testWidgets('a failed PYNQ connectivity test reports the reason', (
    WidgetTester tester,
  ) async {
    fakeTargetRegistry.connectivityTestError = Exception('ssh: auth failed');
    await pumpManagePynqTargets(tester);

    await tester.tap(find.byKey(const Key('hardware-target-test-pynq-1')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('ssh: auth failed'), findsWidgets);
    expect(
      find.byKey(const Key('hardware-target-test-pynq-1')),
      findsOneWidget,
    );
  });

  testWidgets(
    'StudioScreen deploy panel shows Manage Targets for SC-NeuroCore FPGA',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockApi),
            studioTargetRegistryServiceProvider.overrideWithValue(
              fakeTargetRegistry,
            ),
            scNeuroCoreTargetServiceProvider.overrideWithValue(
              fakeScNeuroCoreService,
            ),
            workspaceBootstrapProvider.overrideWithValue(
              const WorkspaceBootstrap(
                initialLocation: '/?panel=deploy&target=sc_neurocore_fpga',
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
      await tester.pumpAndSettle();
      await _seedTrainingHistory(tester);
      await _openManageTargetsFor(tester, 'sc_neurocore_fpga');

      expect(
        find.text('Manage SC-NeuroCore (FPGA RTL) targets'),
        findsOneWidget,
      );
      expect(find.text('Saved targets'), findsOneWidget);
      expect(find.text('FPGA Z2 Dev Board'), findsOneWidget);
      expect(
        find.text('Xilinx • xc7z020 • ssh://xilinx@pynq-z2.local:22'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'StudioScreen Manage Targets dialog opens with warning banner when '
    'launcher service is unreachable',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Simulate the launcher control service being unreachable.
      final failingScNeuroCoreService = _FakeScNeuroCoreTargetService()
        ..fetchError = const LauncherControlApiException(
          503,
          '{"error":"could not reach launcher control service"}',
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockApi),
            studioTargetRegistryServiceProvider.overrideWithValue(
              fakeTargetRegistry,
            ),
            scNeuroCoreTargetServiceProvider.overrideWithValue(
              failingScNeuroCoreService,
            ),
            workspaceBootstrapProvider.overrideWithValue(
              const WorkspaceBootstrap(
                initialLocation: '/?panel=deploy&target=sc_neurocore_fpga',
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
      await tester.pumpAndSettle();
      await _seedTrainingHistory(tester);
      await _openManageTargetsFor(tester, 'sc_neurocore_fpga');

      // Bug 1 fix: dialog must open even when the service is down.
      expect(
        find.text('Manage SC-NeuroCore (FPGA RTL) targets'),
        findsOneWidget,
      );
      // Warning banner must be visible with the error summary.
      expect(find.byType(NmtkStatusBanner), findsAtLeastNWidgets(1));
      // Empty list message is visible because the fetch failed (label is
      // lowercased by the dialog to read naturally as prose).
      expect(
        find.text('No saved sc-neurocore (fpga rtl) devices yet.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'StudioScreen SC-NeuroCore FPGA target add form shows FPGA-specific fields',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockApi),
            studioTargetRegistryServiceProvider.overrideWithValue(
              fakeTargetRegistry,
            ),
            workspaceBootstrapProvider.overrideWithValue(
              const WorkspaceBootstrap(
                initialLocation: '/?panel=deploy&target=sc_neurocore_fpga',
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
      await tester.pumpAndSettle();
      await _seedTrainingHistory(tester);
      await _openManageTargetsFor(tester, 'sc_neurocore_fpga');
      await tester.tap(find.text('Add new target'));
      await tester.pumpAndSettle();

      expect(find.text('Add SC-NeuroCore (FPGA RTL) target'), findsOneWidget);
      expect(find.text('Display name'), findsOneWidget);
      expect(find.text('FPGA family'), findsOneWidget);
      expect(find.text('FPGA Part Number (Device Spec)'), findsOneWidget);
      expect(find.text('Toolchain'), findsOneWidget);
      expect(find.text('Toolchain binary path (on server)'), findsOneWidget);
      expect(find.text('Deployment mode'), findsOneWidget);
      expect(find.text('Output directory (optional)'), findsOneWidget);
      expect(find.text('Set as default target'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    },
  );

  testWidgets('StudioScreen restores legacy analysis deep link into Studio', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          studioTargetRegistryServiceProvider.overrideWithValue(
            fakeTargetRegistry,
          ),
          workspaceBootstrapProvider.overrideWithValue(
            const WorkspaceBootstrap(initialLocation: '/?panel=analysis'),
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
    await _seedTrainingHistoryAndExpandDeploy(tester);

    expect(find.text('Deploy to'), findsNothing);
  });

  // ── D2 tests ──────────────────────────────────────────────────────────────

  testWidgets('StudioScreen deploy panel shows CNL/Canvas view-mode toggle', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(mockApi)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StudioScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(StudioScreen)),
    );
    container
        .read(workspaceProvider.notifier)
        .setActivePipelineStep('defineModel');
    await tester.pumpAndSettle();

    // The mutually-exclusive CNL/NIR/Canvas `ZetaSegmentedControl` (keyed
    // 'cnl-view-toggle' / 'canvas-view-toggle') was replaced by dockable
    // CNL Editor / NIR Importer side-panel toggles in commit `1e9a94e9`
    // ("Cnl canvasses fix") — the canvas body is now always visible and the
    // CNL/NIR panels toggle on top of it rather than switching views. Assert
    // on the surviving toggle controls instead.
    expect(find.byTooltip('CNL Editor'), findsOneWidget);
    expect(find.byTooltip('NIR Importer'), findsOneWidget);
  });

  testWidgets(
    'StudioScreen switches to Canvas view when canvas toggle is tapped',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(mockApi)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: StudioScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      container
          .read(workspaceProvider.notifier)
          .setActivePipelineStep('defineModel');
      await tester.pumpAndSettle();

      // Initially in CNL mode.
      expect(
        container.read(studioViewModeProvider).viewMode,
        StudioViewMode.cnl,
      );

      // Tap the Canvas toggle segment.
      await _setViewMode(tester, StudioViewMode.canvas);

      expect(
        container.read(studioViewModeProvider).viewMode,
        StudioViewMode.canvas,
      );

      // Tap back to CNL.
      await _setViewMode(tester, StudioViewMode.cnl);

      expect(
        container.read(studioViewModeProvider).viewMode,
        StudioViewMode.cnl,
      );
    },
  );

  testWidgets('StudioScreen syncs canvas parameter edits back to CNL', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    when(mockApi.parse(any)).thenAnswer(
      (_) async => const ParseResult(sentences: [], total: 0, errors: 0),
    );
    when(mockApi.validate(any)).thenAnswer(
      (_) async => const ValidationResult(
        overall: true,
        layer1: Layer1Result(overall: true, passed: [], failed: []),
        layer2: Layer2Result(
          overall: true,
          checksPassed: [],
          checksFailed: [],
          neuronsFound: [],
        ),
      ),
    );

    final canvasApi = _SyncingCanvasApiClient();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(mockApi),
        canvas_sync.apiClientProvider.overrideWithValue(canvasApi),
        // Suppress pipeline HTTP calls to avoid extra widget rebuilds / layout
        // overflow during pumpAndSettle — canvas→CNL sync is what we test here.
        pipelineProvider.overrideWith(() => _NoOpPipelineController()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StudioScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    container
        .read(studioViewModeProvider.notifier)
        .setMode(StudioViewMode.canvas);
    // loadProjectGraph (not setGraph) triggers _triggerGenerateCnl so the
    // initial canvas state propagates to specTextProvider via canonicalEditorProvider.
    container
        .read(canvasProvider.notifier)
        .loadProjectGraph(
          CanvasGraph(
            nodes: [
              CanvasNode(
                id: 'sensory',
                componentId: 'lif_population',
                parameters: const {'name': 'sensory', 'n_neurons': 10},
                position: const [100.0, 100.0],
              ),
            ],
            edges: const [],
            metadata: const {},
          ),
        );
    await tester.pumpAndSettle();

    expect(container.read(specTextProvider), contains('10 neurons'));

    container.read(canvasProvider.notifier).updateNodeParameters(
      'sensory',
      const {'name': 'sensory', 'n_neurons': 20},
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    // Updating specTextProvider re-arms the CNL->canvas echo-prevention
    // debounce (studio_sync_notifier.dart's scheduleCnlToCanvasDebounced,
    // 400ms) as a side effect close to the end of the pumpAndSettle loop;
    // pumpAndSettle stops once no frame is scheduled, which can leave that
    // timer still pending. Flush it explicitly so the test doesn't fail on
    // a leftover timer.
    await tester.pump(const Duration(milliseconds: 500));

    expect(container.read(specTextProvider), contains('20 neurons'));
  });

  testWidgets('StudioScreen canvas mode uses the compact canvas workbench', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(mockApi),
        canvas_sync.apiClientProvider.overrideWithValue(
          _SyncingCanvasApiClient(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StudioScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _setViewMode(tester, StudioViewMode.canvas);

    expect(find.byKey(const Key('pipeline-panel-page-view')), findsNothing);
  });

  testWidgets(
    'StudioScreen shows the canvas workspace only on canvas pipeline steps',
    (WidgetTester tester) async {
      // Superseded by the ponytail restructure (commit 1e9a94e9 and
      // predecessors): the CNL/NIR/Canvas view-mode toggle and the
      // pipeline-panel-page-view/canvas-empty-state keys it drove were
      // removed. "Canvas vs pipeline workspace" is now determined purely by
      // which pipeline step is active — defineModel/defineTrain/defineEval
      // render CanvasScreen full-bleed, other steps don't. See
      // pipeline_stage_area.dart's kCanvasSteps / _buildStepContent.
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(mockApi)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: StudioScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default step (selectData) is NOT a canvas step.
      expect(find.byType(CanvasScreen), findsNothing);

      container
          .read(workspaceProvider.notifier)
          .setActivePipelineStep('defineModel');
      await tester.pumpAndSettle();

      // defineModel is a canvas step
      expect(find.byType(CanvasScreen), findsWidgets);

      container
          .read(workspaceProvider.notifier)
          .setActivePipelineStep('selectData');
      await tester.pumpAndSettle();

      expect(find.byType(CanvasScreen), findsNothing);

      container
          .read(workspaceProvider.notifier)
          .setActivePipelineStep('defineModel');
      await tester.pumpAndSettle();

      expect(find.byType(CanvasScreen), findsWidgets);
    },
  );

  testWidgets('StudioScreen compact layout renders without play button', (
    WidgetTester tester,
  ) async {
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
          home: Scaffold(body: StudioScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('play-stop-button')), findsNothing);
  });

  testWidgets('StudioScreen compact workspace state can switch panels', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(mockApi),
        workspaceBootstrapProvider.overrideWithValue(
          const WorkspaceBootstrap(initialLocation: '/?panel=validation'),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StudioScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(workspaceProvider).activePanel, 'validation');

    container.read(workspaceProvider.notifier).setActivePanel('comparison');
    await tester.pumpAndSettle();

    expect(container.read(workspaceProvider).activePanel, 'comparison');
  });

  testWidgets('StudioScreen debounces parse and validate while typing in CNL', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    _stubPipelineApi(mockApi);

    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(mockApi),
        canvas_sync.apiClientProvider.overrideWithValue(
          _SyncingCanvasApiClient(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await _pumpStudio(tester, container);
    clearInteractions(mockApi);

    // Go to defineModel to show CNL Editor
    container
        .read(workspaceProvider.notifier)
        .setActivePipelineStep('defineModel');
    await tester.pumpAndSettle();

    // Open CNL Editor
    await tester.tap(find.byTooltip('CNL Editor'));
    await tester.pumpAndSettle();

    final editorFinder = find.byType(TextField);
    await tester.showKeyboard(editorFinder);

    await tester.enterText(editorFinder, 'neuron');
    await tester.pump();

    await tester.enterText(editorFinder, 'neuron A');
    await tester.pump();

    await tester.enterText(editorFinder, 'neuron AB');
    await tester.pump();

    verifyNever(mockApi.parse(any));
    verifyNever(
      mockApi.validate(
        any,
        params: anyNamed('params'),
        backend: anyNamed('backend'),
      ),
    );

    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    verify(mockApi.parse('neuron AB')).called(1);
    verify(
      mockApi.validate(
        'neuron AB',
        params: anyNamed('params'),
        backend: anyNamed('backend'),
      ),
    ).called(1);
  });

  // ── D3 tests ──────────────────────────────────────────────────────────────

  testWidgets('StudioScreen header shows no play button (auto-run mode)', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(mockApi)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StudioScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Play button has been removed — parse/validate runs automatically.
    expect(find.byKey(const Key('play-stop-button')), findsNothing);
    expect(find.byKey(const Key('play-icon')), findsNothing);
    expect(find.byKey(const Key('stop-icon')), findsNothing);
  });

  testWidgets('StudioScreen Cmd+Enter triggers run when validation passes', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(mockApi),
        canvas_sync.apiClientProvider.overrideWithValue(
          _SyncingCanvasApiClient(),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Use a Completer that never resolves so the pipeline stays in `running`
    // long enough for us to assert on generateStatus before it transitions.
    final generateCompleter = Completer<GenerateResult>();
    addTearDown(() {
      if (!generateCompleter.isCompleted) {
        generateCompleter.completeError(Exception('test-teardown'));
      }
    });
    when(mockApi.generate(any)).thenAnswer((_) => generateCompleter.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StudioScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Seed a non-empty spec so runGenerateAndSimulate doesn't bail on empty.
    await container
        .read(specTextProvider.notifier)
        .set('neuron A with 10 neurons');
    await tester.pump();

    // Ensure the shortcuts layer receives keyboard events by giving focus to
    // the nearest focusable descendant of StudioScreen.
    final studioElement = tester.element(find.byType(StudioScreen));
    FocusScope.of(studioElement).requestFocus();
    await tester.pump();

    // Seed a passing validation result so the run is enabled.
    container.read(pipelineProvider.notifier).state = const PipelineState(
      validateStatus: StepStatus.success,
      validateResult: ValidationResult(
        overall: true,
        layer1: Layer1Result(overall: true, passed: [], failed: []),
        layer2: Layer2Result(
          overall: true,
          checksPassed: [],
          checksFailed: [],
          neuronsFound: [],
        ),
      ),
    );
    await tester.pump();

    // Send Cmd+Enter.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    // The pipeline should have transitioned to a running state.
    expect(container.read(pipelineProvider).generateStatus, StepStatus.running);
    await tester.pump(const Duration(milliseconds: 500));
  });

  // ── D2 bidirectional-sync regression tests ─────────────────────────────────

  testWidgets(
    'StudioScreen Canvas→CNL: cnlSpecProvider change updates specTextProvider',
    (WidgetTester tester) async {
      // Regression for the count-check bug that silently skipped parameter-only
      // canvas changes because node/edge counts stayed the same.  The fix listens
      // to canvas_sync.cnlSpecProvider directly so ALL CNL-relevant mutations
      // (including parameter updates) propagate to specTextProvider.
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(mockApi)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: StudioScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to canvas mode — canvas→CNL auto-sync only fires in canvas mode so
      // the user's CNL editor is not overwritten by background canvas mutations.
      container
          .read(studioViewModeProvider.notifier)
          .setMode(StudioViewMode.canvas);
      await tester.pump();

      // Simulate the canvas producing a new canonical document (as CanvasController
      // does internally via _pushToCanonical → canonicalDocProvider.updateFromCanvas).
      // The studio screen listens to canonicalDocProvider and mirrors the CNL
      // back into specTextProvider when not in CNL mode.
      const canvasCnl = 'lif1 = LIF neuron with threshold 0.5';
      container
          .read(canonicalDocProvider.notifier)
          .setDocument(
            const canonical_doc.CanonicalEditorDocument(
              irJson: {},
              cnlText: canvasCnl,
            ),
          );

      // Allow the listener to propagate synchronously and rebuild.
      await tester.pump();

      // specTextProvider must reflect the canvas-generated CNL.
      expect(container.read(specTextProvider), equals(canvasCnl));

      // Updating specTextProvider re-arms the CNL->canvas echo-prevention
      // debounce (studio_sync_notifier.dart's scheduleCnlToCanvasDebounced,
      // 400ms). Flush it so the test doesn't fail on a leftover timer.
      await tester.pump(const Duration(milliseconds: 500));
    },
  );

  testWidgets(
    'StudioScreen saves the workspace through the native adapter when the '
    'toolbar Save button is tapped',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      _stubPipelineApi(mockApi);

      final backend = _RecordingNativeFileBackend(
        saveWorkspaceFileResult: const SaveResult(
          outcome: SaveOutcome.saved,
          path: '/tmp/session.nmtk',
        ),
      );
      final container = _buildStudioContainer(
        mockApi: mockApi,
        backend: backend,
        bootstrap: WorkspaceBootstrap(
          initialRestoreState: <String, Object?>{
            'workspace': <String, Object?>{
              'files': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'draft',
                  'name': 'Draft',
                  'canonicalDocument': _canonicalDocJson('alpha spec'),
                  'dirty': true,
                  'isUntitled': true,
                },
              ],
              'activeFileId': 'draft',
            },
          },
        ),
      );
      addTearDown(container.dispose);
      await _pumpStudio(tester, container);

      await tester.tap(find.byTooltip('Save workspace'));
      await tester.pumpAndSettle();

      expect(backend.lastWorkspaceSuggestedName, 'session.nmtk');
      expect(backend.lastWorkspaceContents, contains('alpha spec'));
      expect(backend.lastTextSuggestedName, isNull);
      expect(find.text('Saved to /tmp/session.nmtk'), findsOneWidget);
    },
  );

  testWidgets('Start Fresh keeps Model, Training, and Eval canvases empty', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _stubPipelineApi(mockApi);

    await ServerConfigService.setString(
      WorkspaceController.workspaceStorageKey,
      jsonEncode(<String, Object?>{
        'version': 1,
        'workspace': <String, Object?>{
          'files': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'saved',
              'name': 'Saved model',
              'canonicalDocument': _canonicalDocJson(
                'saved = LIF neuron with threshold 1.0',
              ),
              'dirty': false,
              'isUntitled': false,
            },
          ],
          'activeFileId': 'saved',
        },
      }),
    );

    final container = _buildStudioContainer(
      mockApi: mockApi,
      backend: _RecordingNativeFileBackend(),
    );
    addTearDown(container.dispose);
    await _pumpStudio(tester, container);

    expect(find.text('Restore previous session?'), findsOneWidget);
    container
        .read(canvasProvider.notifier)
        .addPipelineDagNode(
          PipelinePhaseId.train,
          const PipelineDagNode(
            id: 'stale_train',
            type: PipelineDagNodeType.forwardPass,
          ),
        );
    container
        .read(canvasProvider.notifier)
        .addPipelineDagNode(
          PipelinePhaseId.eval,
          const PipelineDagNode(
            id: 'stale_eval',
            type: PipelineDagNodeType.accuracyMetric,
          ),
        );

    await tester.tap(find.text('Start Fresh'));
    await tester.pumpAndSettle();

    var canvasState = container.read(canvasProvider);
    expect(canvasState.graph.nodes, isEmpty);
    expect(canvasState.pipelinePhases.isEmpty, isTrue);

    container
        .read(workspaceProvider.notifier)
        .setActivePipelineStep('defineTrain');
    await tester.pumpAndSettle();
    canvasState = container.read(canvasProvider);
    expect(canvasState.pipelinePhases.train.nodes, isEmpty);

    container
        .read(workspaceProvider.notifier)
        .setActivePipelineStep('defineEval');
    await tester.pumpAndSettle();
    canvasState = container.read(canvasProvider);
    expect(canvasState.pipelinePhases.eval.nodes, isEmpty);
  });

  testWidgets(
    'StudioScreen keeps the restore choice usable when startup model sync fails',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      _stubPipelineApi(mockApi);

      await ServerConfigService.setString(
        WorkspaceController.workspaceStorageKey,
        jsonEncode(<String, Object?>{
          'version': 1,
          'workspace': <String, Object?>{
            'files': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'saved',
                'name': 'Saved model',
                'canonicalDocument': _canonicalDocJson(
                  'saved = LIF neuron with threshold 1.0',
                ),
                'dirty': false,
                'isUntitled': false,
              },
            ],
            'activeFileId': 'saved',
          },
        }),
      );

      final container = _buildStudioContainer(
        mockApi: mockApi,
        backend: _RecordingNativeFileBackend(),
        syncApi: _FailingCanonicalApiClient(),
      );
      addTearDown(container.dispose);
      await _pumpStudio(tester, container);

      await container
          .read(canonicalDocProvider.notifier)
          .updateFromCnl('unsupported startup model');
      await tester.pump();

      expect(find.text('Restore previous session?'), findsOneWidget);
      expect(find.textContaining('Model sync failed'), findsNothing);

      await tester.tap(find.text('Start Fresh'));
      await tester.pumpAndSettle();

      await container
          .read(canonicalDocProvider.notifier)
          .updateFromCnl('unsupported edited model');
      await tester.pump();

      expect(find.textContaining('Model sync failed'), findsOneWidget);
      expect(find.textContaining('unsupported model'), findsNothing);
    },
  );

  testWidgets(
    'StudioScreen workspace save captures Setup, Train canvas, Eval canvas, '
    'and Results — not just the Model',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      _stubPipelineApi(mockApi);

      final backend = _RecordingNativeFileBackend(
        saveWorkspaceFileResult: const SaveResult(
          outcome: SaveOutcome.saved,
          path: '/tmp/session.nmtk',
        ),
      );
      final container = _buildStudioContainer(
        mockApi: mockApi,
        backend: backend,
        bootstrap: WorkspaceBootstrap(
          initialRestoreState: <String, Object?>{
            'workspace': <String, Object?>{
              'files': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'draft',
                  'name': 'Draft',
                  'canonicalDocument': _canonicalDocJson('the model spec'),
                  'dirty': true,
                  'isUntitled': true,
                },
              ],
              'activeFileId': 'draft',
            },
          },
        ),
      );
      addTearDown(container.dispose);
      await _pumpStudio(tester, container);

      // Populate the Train and Eval canvases (steps 3/4) through the same
      // provider method the pipeline-phase canvas widgets call on a real
      // node drop.
      container
          .read(canvasProvider.notifier)
          .addPipelineDagNode(
            PipelinePhaseId.train,
            const PipelineDagNode(
              id: 'train_node',
              type: PipelineDagNodeType.forwardPass,
            ),
          );
      container
          .read(canvasProvider.notifier)
          .addPipelineDagNode(
            PipelinePhaseId.eval,
            const PipelineDagNode(
              id: 'eval_node',
              type: PipelineDagNodeType.forwardPass,
            ),
          );

      // Populate Results (step 6): a completed simulation plus training
      // history, the same state a real Run would leave behind.
      container
          .read(canvas_sim.simulationProvider.notifier)
          .restoreSnapshot(
            resultsJson: const <String, dynamic>{'status': 'completed'},
          );
      final resultSession = container.read(
        studioResultSessionProvider.notifier,
      );
      resultSession.beginAttempt(
        platforms: const ['snntorch_sim'],
        provenance: const StudioResultProvenance(
          workspaceName: 'Save test',
          modelFingerprint: 'save-model',
        ),
      );
      resultSession.recordEpoch(
        'snntorch_sim',
        const TrainingEpochEvent(epoch: 1, loss: 0.42),
      );
      resultSession.markComplete('snntorch_sim');
      await tester.pump();

      await tester.tap(find.byTooltip('Save workspace'));
      await tester.pump();

      final saved =
          jsonDecode(backend.lastWorkspaceContents!) as Map<String, dynamic>;
      final savedFile =
          ((saved['workspace'] as Map)['files'] as List).first as Map;
      expect(
        savedFile['canonicalDocument'],
        isNotNull,
        reason: 'Model must be saved',
      );

      final canvas = saved['canvas'] as Map;
      final phases = canvas['pipelinePhases'] as Map;
      expect(
        (phases['train'] as Map)['nodes'],
        isNotEmpty,
        reason: 'Train canvas must be saved',
      );
      expect(
        (phases['eval'] as Map)['nodes'],
        isNotEmpty,
        reason: 'Eval canvas must be saved',
      );
      expect(
        canvas['simulationResults'],
        isNotNull,
        reason: 'Results (simulation) must be saved',
      );
      expect(
        saved['resultSnapshot'],
        isNotEmpty,
        reason: 'The compact result snapshot must be saved separately',
      );
      expect(
        canvas.containsKey('trainingHistory'),
        isFalse,
        reason: 'Legacy unbounded training history must not be re-saved',
      );
    },
  );

  testWidgets(
    'StudioScreen switching active files keeps spec text sourced from workspace content',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      _stubPipelineApi(mockApi);

      final container = _buildStudioContainer(
        mockApi: mockApi,
        backend: _RecordingNativeFileBackend(),
        bootstrap: const WorkspaceBootstrap(
          initialRestoreState: <String, Object?>{
            'workspace': <String, Object?>{
              'files': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'alpha',
                  'name': 'Alpha.cnl',
                  'canonicalDocument': <String, Object?>{
                    'ir_json': <String, Object?>{},
                    'cnl_text': 'alpha spec',
                  },
                  'dirty': false,
                  'isUntitled': false,
                },
                <String, Object?>{
                  'id': 'beta',
                  'name': 'Beta.cnl',
                  'canonicalDocument': <String, Object?>{
                    'ir_json': <String, Object?>{},
                    'cnl_text': 'beta spec',
                  },
                  'dirty': false,
                  'isUntitled': false,
                },
              ],
              'activeFileId': 'alpha',
            },
          },
        ),
      );
      addTearDown(container.dispose);
      await _pumpStudio(tester, container);

      expect(container.read(workspaceProvider).activeFileId, 'alpha');
      expect(
        container
            .read(workspaceProvider)
            .activeFile
            ?.canonicalDocument
            ?.cnlText,
        'alpha spec',
      );
      expect(container.read(specTextProvider), 'alpha spec');

      container.read(workspaceProvider.notifier).setActiveFile('beta');
      await tester.pump();

      expect(container.read(workspaceProvider).activeFileId, 'beta');
      expect(
        container
            .read(workspaceProvider)
            .activeFile
            ?.canonicalDocument
            ?.cnlText,
        'beta spec',
      );
      expect(container.read(specTextProvider), 'beta spec');
    },
  );

  test(
    'workspaceRecentActivitiesProvider does not notify on spec edits',
    () async {
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          canvas_sync.apiClientProvider.overrideWithValue(
            _SyncingCanvasApiClient(),
          ),
        ],
      );
      addTearDown(container.dispose);

      var notifications = 0;
      final sub = container.listen(
        workspaceRecentActivitiesProvider,
        (_, _) => notifications++,
        fireImmediately: true,
      );
      addTearDown(sub.close);

      expect(notifications, 1);

      await container.read(specTextProvider.notifier).set('edited spec');

      expect(notifications, 1);
    },
  );

  testWidgets(
    'StudioScreen leaves dirty file unchanged when save is cancelled',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      _stubPipelineApi(mockApi);

      final backend = _RecordingNativeFileBackend(
        saveWorkspaceFileResult: const SaveResult(
          outcome: SaveOutcome.cancelled,
        ),
      );
      final container = _buildStudioContainer(
        mockApi: mockApi,
        backend: backend,
        bootstrap: WorkspaceBootstrap(
          initialRestoreState: <String, Object?>{
            'workspace': <String, Object?>{
              'files': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'draft',
                  'name': 'Draft.cnl',
                  'canonicalDocument': _canonicalDocJson('alpha spec'),
                  'dirty': true,
                  'isUntitled': false,
                },
              ],
              'activeFileId': 'draft',
            },
          },
        ),
      );
      addTearDown(container.dispose);
      await _pumpStudio(tester, container);

      await tester.tap(find.byTooltip('Save workspace'));
      await tester.pumpAndSettle();

      expect(container.read(workspaceProvider).activeFile?.dirty, isTrue);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('StudioScreen reopens workspace with cached generated code', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _stubPipelineApi(mockApi);

    const content = 'cached spec';
    final container = _buildStudioContainer(
      mockApi: mockApi,
      backend: _RecordingNativeFileBackend(),
      bootstrap: WorkspaceBootstrap(
        initialLocation: '/?panel=generate',
        initialRestoreState: <String, Object?>{
          'workspace': <String, Object?>{
            'files': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'cached',
                'name': 'Cached.cnl',
                'canonicalDocument': _canonicalDocJson(content),
                'dirty': false,
                'isUntitled': false,
                'pipelineCache': _pipelineCacheJson(content),
              },
            ],
            'activeFileId': 'cached',
          },
        },
      ),
    );
    addTearDown(container.dispose);

    await _pumpStudio(tester, container);
    await _seedTrainingHistoryAndExpandDeploy(tester);
    // "View NIR Artifact" lives inside the SC-NeuroCore FPGA workspace page,
    // reached via the hardware table's Configure button rather than
    // rendered inline.
    await tester.tap(
      find.byKey(const Key('hardware-target-open-sc_neurocore_fpga')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View NIR Artifact'));
    await tester.pumpAndSettle();

    expect(find.text('cached round-trip cnl'), findsOneWidget);
    expect(
      find.text('Run the model to see\nround-trip CNL output.'),
      findsNothing,
    );
  });

  testWidgets('StudioScreen maps legacy preview panel restores to deploy', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _stubPipelineApi(mockApi);

    const content = 'cached spec';
    final container = _buildStudioContainer(
      mockApi: mockApi,
      backend: _RecordingNativeFileBackend(),
      bootstrap: WorkspaceBootstrap(
        initialLocation: '/?panel=simulation',
        initialRestoreState: <String, Object?>{
          'workspace': <String, Object?>{
            'files': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'cached',
                'name': 'Cached.cnl',
                'canonicalDocument': _canonicalDocJson(content),
                'dirty': false,
                'isUntitled': false,
                'pipelineCache': _pipelineCacheJson(content),
              },
            ],
            'activeFileId': 'cached',
          },
        },
      ),
    );
    addTearDown(container.dispose);

    await _pumpStudio(tester, container);
    await _seedTrainingHistoryAndExpandDeploy(tester);
    await tester.tap(
      find.byKey(const Key('hardware-target-open-sc_neurocore_fpga')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View NIR Artifact'));
    await tester.pumpAndSettle();

    expect(container.read(workspaceProvider).activePanel, 'deploy');
    expect(find.text('Compiled Artifacts'), findsWidgets);
    expect(find.text('roundtrip.cnl'), findsOneWidget);
    expect(find.text('CNL'), findsWidgets);
  });

  testWidgets('StudioScreen hides cached output after editing reopened file', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _stubPipelineApi(mockApi);

    const content = 'cached spec';
    final container = _buildStudioContainer(
      mockApi: mockApi,
      backend: _RecordingNativeFileBackend(),
      bootstrap: WorkspaceBootstrap(
        initialLocation: '/?panel=generate',
        initialRestoreState: <String, Object?>{
          'workspace': <String, Object?>{
            'files': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'cached',
                'name': 'Cached.cnl',
                'canonicalDocument': _canonicalDocJson(content),
                'dirty': false,
                'isUntitled': false,
                'pipelineCache': _pipelineCacheJson(content),
              },
            ],
            'activeFileId': 'cached',
          },
        },
      ),
    );
    addTearDown(container.dispose);
    await _pumpStudio(tester, container);
    await _seedTrainingHistoryAndExpandDeploy(tester);
    await tester.tap(
      find.byKey(const Key('hardware-target-open-sc_neurocore_fpga')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View NIR Artifact'));
    await tester.pumpAndSettle();

    expect(find.text('cached round-trip cnl'), findsOneWidget);

    container
        .read(canonicalDocProvider.notifier)
        .setDocument(
          const canonical_doc.CanonicalEditorDocument(
            irJson: {},
            cnlText: 'edited spec',
          ),
        );
    container
        .read(pipelineProvider.notifier)
        .hydrateCachedResultsForFile(
          container.read(workspaceProvider).activeFile,
        );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('cached round-trip cnl'), findsNothing);
    expect(
      find.text('Run the model to see\nround-trip CNL output.'),
      findsOneWidget,
    );
  });

  testWidgets('Invalid restored pipeline step falls back without crashing', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(2560, 1440);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _stubPipelineApi(mockApi);

    final container = _buildStudioContainer(
      mockApi: mockApi,
      backend: _RecordingNativeFileBackend(),
      bootstrap: const WorkspaceBootstrap(
        initialRestoreState: <String, Object?>{
          'workspace': <String, Object?>{'activePipelineStep': 'comparison'},
        },
      ),
    );
    addTearDown(container.dispose);

    await _pumpStudio(tester, container);

    expect(tester.takeException(), isNull);
    expect(container.read(workspaceProvider).activePipelineStep, 'selectData');
  });

  testWidgets('Collapsing left pane keeps right step as activeStep', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(3000, 1440);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _stubPipelineApi(mockApi);

    // Start mid-stage: the stepper only draws "Close left pane" in the
    // connector *before* the left pane, so the left step of the split pair
    // cannot be the first step of its stage.
    final container = _buildStudioContainer(
      mockApi: mockApi,
      backend: _RecordingNativeFileBackend(),
      bootstrap: const WorkspaceBootstrap(
        initialRestoreState: <String, Object?>{
          'workspace': <String, Object?>{
            'activePipelineStep': 'defineTrain',
            'selectedPlatforms': ['snntorch'],
          },
        },
      ),
    );
    addTearDown(container.dispose);
    await _pumpStudio(tester, container);

    // Active step is Training. Its after-step split button opens 'defineEval'
    // on the right.
    final addNext = find.byTooltip('Open split view').last;
    await tester.tap(addNext);
    await tester.pumpAndSettle(); // wait for split animation to complete

    // Split view: left = 'defineTrain', right = 'defineEval'.
    // Tap "Close left pane" → should keep 'defineEval' active.
    final closeLeft = find.byTooltip('Close left pane');
    expect(closeLeft, findsOneWidget);
    await tester.tap(closeLeft);
    await tester.pumpAndSettle(); // complete collapse animation + page jump

    // Riverpod state must reflect the kept step.
    expect(
      container.read(workspaceProvider).activePipelineStep,
      'defineEval',
      reason: 'Closing the left pane must keep the right pane active',
    );
    // 'defineEval' is the last step of the Design stage, so only the
    // before-step split button (between 'defineTrain' and 'defineEval')
    // remains — the after-step slot has no same-stage step to its right. If
    // the page controller landed on the wrong page, this count (and the
    // assertion above) would be off.
    expect(
      find.byTooltip('Open split view'),
      findsOneWidget,
      reason:
          "'defineEval' ends the Design stage — only the before-step split "
          'button should remain',
    );
  });

  testWidgets('changing main stage collapses a same-stage split', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(3000, 1440);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _stubPipelineApi(mockApi);

    // Start at the final Design child and open its same-stage neighbor.
    final container = _buildStudioContainer(
      mockApi: mockApi,
      backend: _RecordingNativeFileBackend(),
      bootstrap: const WorkspaceBootstrap(
        initialRestoreState: <String, Object?>{
          'workspace': <String, Object?>{
            'activePipelineStep': 'defineEval',
            'selectedPlatforms': ['snntorch'],
          },
        },
      ),
    );
    addTearDown(container.dispose);
    await _pumpStudio(tester, container);

    expect(find.byTooltip('Open Run beside Evaluation'), findsNothing);
    await tester.tap(find.byTooltip('Open split view'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close left pane'), findsOneWidget);

    await tester.tap(find.text('Execute'));
    await tester.pumpAndSettle();

    expect(
      container.read(workspaceProvider).activePipelineStep,
      'run',
      reason: 'Selecting Execute should open its first available child',
    );
    expect(find.byTooltip('Close left pane'), findsNothing);
    expect(find.byTooltip('Close right pane'), findsNothing);
  });
}

/// Builds the `canonicalDocument` restore-payload JSON for a bootstrap file
/// entry carrying [cnlText] as its CNL source — `WorkspaceFile` no longer has
/// a standalone `content` field, so file content is seeded this way.
Map<String, Object?> _canonicalDocJson(String cnlText) {
  return <String, Object?>{'ir_json': <String, Object?>{}, 'cnl_text': cnlText};
}

Map<String, Object?> _pipelineCacheJson(
  String content, {
  bool includeNirArtifact = false,
}) {
  final json = <String, Object?>{
    'sourceHash': WorkspacePipelineCache.sourceHashFor(content),
    'generatedAt': '2026-05-11T12:00:00.000',
    'simulatedAt': '2026-05-11T12:00:01.000',
    'generateResult': const GenerateResult(
      network: NetworkGraph(
        nodes: <NetworkNode>[
          NetworkNode(
            id: 'n1',
            type: 'ensemble',
            subtype: 'lif',
            label: 'Neuron',
            params: <String, Object?>{},
          ),
        ],
        edges: <NetworkEdge>[],
      ),
      cnlDocument: 'cached round-trip cnl',
      nirCode: 'cached_nir_code',
    ).toJson(),
    'simulationResult': const SimulationResult(
      duration: 1.0,
      dt: 0.001,
      timesteps: 1000,
      wallTimeSeconds: 0.5,
      probes: <String, ProbeData>{
        'sensory': ProbeData(
          type: 'spike_raster',
          times: <double>[0.1, 0.2],
          neuronIndices: <int>[0, 1],
        ),
      },
      summary: SimulationSummary(
        sensorySpikeCount: 2,
        motorSpikeCount: 0,
        sensoryMeanRate: 2,
        motorMeanRate: 0,
      ),
    ).toJson(),
  };
  if (includeNirArtifact) {
    json['nirArtifactCache'] = _nirArtifactCacheJson(content);
  }
  return json;
}

Map<String, Object?> _nirArtifactCacheJson(String content) {
  return <String, Object?>{
    'sourceHash': WorkspacePipelineCache.sourceHashFor(content),
    'savedAt': '2026-05-11T12:00:02.000',
    'filename': 'network.nir',
    'mimeType': 'application/octet-stream',
    'payloadBase64': 'ECAwQA==',
  };
}

ProviderContainer _buildStudioContainer({
  required MockApiClient mockApi,
  required NativeFileBackend backend,
  WorkspaceBootstrap bootstrap = const WorkspaceBootstrap(),
  canvas_api.ApiClient? syncApi,
}) {
  return ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(mockApi),
      canvas_sync.apiClientProvider.overrideWithValue(
        syncApi ?? _SyncingCanvasApiClient(),
      ),
      nativeFileAdapterProvider.overrideWithValue(FileAdapter(backend)),
      workspaceBootstrapProvider.overrideWithValue(bootstrap),
    ],
  );
}

Future<void> _pumpStudio(
  WidgetTester tester,
  ProviderContainer container, {
  Widget? workspaceHeaderAction,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StudioScreen(workspaceHeaderAction: workspaceHeaderAction),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _stubPipelineApi(MockApiClient mockApi) {
  when(mockApi.parse(any)).thenAnswer(
    (_) async => const ParseResult(sentences: [], total: 0, errors: 0),
  );
  when(
    mockApi.validate(
      any,
      params: anyNamed('params'),
      backend: anyNamed('backend'),
    ),
  ).thenAnswer(
    (_) async => const ValidationResult(
      overall: true,
      layer1: Layer1Result(overall: true, passed: [], failed: []),
      layer2: Layer2Result(
        overall: true,
        checksPassed: [],
        checksFailed: [],
        neuronsFound: [],
      ),
    ),
  );
}

class _RecordingNativeFileBackend implements NativeFileBackend {
  _RecordingNativeFileBackend({
    this.saveWorkspaceFileResult = const SaveResult(outcome: SaveOutcome.saved),
  });

  final SaveResult saveWorkspaceFileResult;

  String? lastTextSuggestedName;
  String? lastTextContents;
  String? lastWorkspaceSuggestedName;
  String? lastWorkspaceContents;

  @override
  Future<List<OpenedTextFile>?> openTextFiles() async => null;

  @override
  Future<OpenedTextFile?> openWorkspaceFile() async => null;

  @override
  Future<OpenedBinaryFile?> openDatasetImport() async => null;

  @override
  Future<SaveResult> saveTextFile({
    required String suggestedName,
    required String contents,
  }) async {
    lastTextSuggestedName = suggestedName;
    lastTextContents = contents;
    return const SaveResult(outcome: SaveOutcome.saved);
  }

  @override
  Future<SaveResult> saveWorkspaceFile({
    required String suggestedName,
    required String contents,
  }) async {
    lastWorkspaceSuggestedName = suggestedName;
    lastWorkspaceContents = contents;
    return saveWorkspaceFileResult;
  }

  @override
  Future<SaveResult> saveBinaryFile({
    required String suggestedName,
    required Uint8List bytes,
    List<String>? allowedExtensions,
  }) async {
    return const SaveResult(outcome: SaveOutcome.saved);
  }
}

class _FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return _FakePlatformNavigationDelegate(params);
  }

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return _FakePlatformWebViewController(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return _FakePlatformWebViewWidget(params);
  }
}

class _FakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  _FakePlatformNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnHttpAuthRequest(
    HttpAuthRequestCallback onHttpAuthRequest,
  ) async {}

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {}

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}

  @override
  Future<void> setOnSSlAuthError(SslAuthErrorCallback onSslAuthError) async {}

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {}

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {}
}

class _FakePlatformWebViewController extends PlatformWebViewController {
  _FakePlatformWebViewController(super.params) : super.implementation();

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
}

class _FakePlatformWebViewWidget extends PlatformWebViewWidget {
  _FakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

AkidaPairedHost _akidaHost({
  String id = 'akida-1',
  String displayName = 'Akida Host A',
  AkidaPairedHostState state = AkidaPairedHostState.ready,
  String lastReadinessMessage = '',
}) {
  return AkidaPairedHost(
    id: id,
    displayName: displayName,
    host: 'akida-linux.local',
    sshPort: 22,
    username: 'neurochip',
    runtimeApiUrl: 'http://akida-linux.local:8002',
    controlApiUrl: 'http://akida-linux.local:8091',
    authMode: AkidaHostAuthMode.password,
    credentialRef: '',
    password: '',
    hasPassword: true,
    sshKeyPath: '',
    remoteInstallRoot: '/opt/neurochip-akida-host',
    serviceUser: 'neurochip',
    hostOs: 'linux',
    pythonVersion: '3.11',
    runtimeMode: AkidaRuntimeMode.remoteSdk,
    state: state,
    lastReadinessMessage: lastReadinessMessage,
    lastVerifiedAt: '',
  );
}

class _FakeStudioTargetRegistryService extends StudioTargetRegistryService {
  _FakeStudioTargetRegistryService() : super();

  String? lastSavedAkidaPassword;
  bool? lastSavedSameHostAsBackend;
  String? lastSavedPynqPassword;
  String? lastSelectedAkidaHostId;

  /// Host ids passed to [testAkidaHostConnection], in order.
  final List<String> connectivityTestedHostIds = <String>[];

  /// When non-null, [testAkidaHostConnection] throws this instead.
  Object? connectivityTestError;

  /// Host ids passed to [provisionAkidaHost], in order.
  final List<String> provisionedHostIds = <String>[];

  /// When non-null, [provisionAkidaHost] throws this instead.
  Object? provisionError;

  /// When non-null, [selectAkidaHost] throws this, driving the
  /// save-succeeded-but-select-failed path.
  Object? selectAkidaHostError;

  /// When non-null, [fetchPynqBoards] throws this error to simulate a
  /// launcher service being unreachable.
  Object? pynqFetchError;

  /// When non-null, [selectPynqBoard] throws this, driving the
  /// save-succeeded-but-select-failed path for PYNQ.
  Object? selectPynqBoardError;

  String? lastSelectedPynqBoardId;
  final List<String> preflightedPynqBoardIds = <String>[];
  final List<String> connectivityTestedPynqBoardIds = <String>[];

  /// Board ids passed to [provisionPynqBoard], in order. Must stay empty for a
  /// connectivity test: the two are deliberately separate steps, because a cold
  /// provision needs 90–100 s and an SSH check needs seconds.
  final List<String> provisionedPynqBoardIds = <String>[];

  @override
  Future<List<AkidaPairedHost>> fetchAkidaHosts() async {
    return const [
      AkidaPairedHost(
        id: 'akida-1',
        displayName: 'Akida Host A',
        host: 'akida-linux.local',
        sshPort: 22,
        username: 'neurochip',
        runtimeApiUrl: 'http://akida-linux.local:8002',
        controlApiUrl: 'http://akida-linux.local:8091',
        authMode: AkidaHostAuthMode.password,
        credentialRef: '',
        password: '',
        hasPassword: true,
        sshKeyPath: '',
        remoteInstallRoot: '/opt/neurochip-akida-host',
        serviceUser: 'neurochip',
        hostOs: 'linux',
        pythonVersion: '3.11',
        runtimeMode: AkidaRuntimeMode.remoteSdk,
        state: AkidaPairedHostState.ready,
        lastReadinessMessage: '',
        lastVerifiedAt: '',
      ),
    ];
  }

  @override
  Future<void> selectAkidaHost(String hostId) async {
    final error = selectAkidaHostError;
    if (error != null) throw error;
    lastSelectedAkidaHostId = hostId;
  }

  @override
  Future<AkidaPairedHost> testAkidaHostConnection(String hostId) async {
    connectivityTestedHostIds.add(hostId);
    final error = connectivityTestError;
    if (error != null) throw error;
    return _akidaHost(
      id: hostId,
      state: AkidaPairedHostState.reachable,
      lastReadinessMessage: 'SSH reachable',
    );
  }

  @override
  Future<AkidaPairedHost> provisionAkidaHost(String hostId) async {
    provisionedHostIds.add(hostId);
    final error = provisionError;
    if (error != null) throw error;
    return _akidaHost(
      id: hostId,
      state: AkidaPairedHostState.ready,
      lastReadinessMessage: 'Runtime installed and running',
    );
  }

  @override
  Future<AkidaPairedHost> saveAkidaHost({
    String? hostId,
    required String displayName,
    required String hostAddress,
    required int sshPort,
    required String username,
    required String authMode,
    required String? password,
    required String sshKeyPath,
    required String runtimeApiUrl,
    required String controlApiUrl,
    required String remoteInstallRoot,
    required String serviceUser,
    bool isDefault = false,
    bool sameHostAsBackend = false,
  }) async {
    lastSavedAkidaPassword = password;
    lastSavedSameHostAsBackend = sameHostAsBackend;
    return AkidaPairedHost(
      id: hostId ?? 'akida-1',
      displayName: displayName,
      host: hostAddress,
      sshPort: sshPort,
      username: username,
      runtimeApiUrl: runtimeApiUrl,
      controlApiUrl: controlApiUrl,
      authMode: AkidaHostAuthMode.password,
      credentialRef: '',
      password: '',
      hasPassword: true,
      sshKeyPath: '',
      remoteInstallRoot: remoteInstallRoot,
      serviceUser: serviceUser,
      hostOs: 'linux',
      pythonVersion: '3.11',
      runtimeMode: AkidaRuntimeMode.remoteSdk,
      state: AkidaPairedHostState.ready,
      lastReadinessMessage: '',
      lastVerifiedAt: '',
      sameHostAsBackend: sameHostAsBackend,
    );
  }

  @override
  Future<List<PynqPairedBoard>> fetchPynqBoards() async {
    if (pynqFetchError != null) {
      // ignore: only_throw_errors
      throw pynqFetchError!;
    }
    return const [
      PynqPairedBoard(
        id: 'pynq-1',
        displayName: 'PYNQ Z2 Dev Board',
        host: 'pynq-z2.local',
        sshPort: 22,
        username: 'xilinx',
        authMode: PynqBoardAuthMode.password,
        credentialRef: '',
        runtimeApiUrl: 'http://pynq-z2.local:8003',
        runtimeApiUrlOverride: '',
        overlayVersion: '',
        state: PynqBoardState.ready,
        lastPreflightStatus: '',
        lastPreflightMessage: '',
        lastRuntimeMode: '',
        hasPassword: true,
        sshKeyPath: '',
        isDefault: false,
      ),
    ];
  }

  @override
  Future<PynqPairedBoard> savePynqBoard({
    String? boardId,
    required String displayName,
    required String hostAddress,
    required int sshPort,
    required String username,
    required String authMode,
    required String password,
    required String sshKeyPath,
    required String runtimeApiUrlOverride,
    required String overlayVersion,
    bool isDefault = false,
  }) async {
    lastSavedPynqPassword = password;
    return PynqPairedBoard(
      id: boardId ?? 'pynq-1',
      displayName: displayName,
      host: hostAddress,
      sshPort: sshPort,
      username: username,
      authMode: PynqBoardAuthMode.password,
      credentialRef: '',
      runtimeApiUrl: 'http://pynq-z2.local:8003',
      runtimeApiUrlOverride: runtimeApiUrlOverride,
      overlayVersion: overlayVersion,
      state: PynqBoardState.ready,
      lastPreflightStatus: '',
      lastPreflightMessage: '',
      lastRuntimeMode: '',
      hasPassword: true,
      sshKeyPath: '',
      isDefault: isDefault,
    );
  }

  @override
  Future<void> selectPynqBoard(String boardId) async {
    final error = selectPynqBoardError;
    if (error != null) throw error;
    lastSelectedPynqBoardId = boardId;
  }

  @override
  Future<String?> fetchSelectedPynqBoardId() async => lastSelectedPynqBoardId;

  @override
  Future<PynqBoardOperationResult> fetchPynqBoardPreflight(
    String boardId,
  ) async {
    preflightedPynqBoardIds.add(boardId);
    final boards = await fetchPynqBoards();
    return PynqBoardOperationResult(board: boards.first);
  }

  @override
  Future<PynqPairedBoard> testPynqBoardConnection(String boardId) async {
    connectivityTestedPynqBoardIds.add(boardId);
    final error = connectivityTestError;
    if (error != null) throw error;
    final boards = await fetchPynqBoards();
    return boards.first;
  }

  @override
  Future<PynqBoardOperationResult> provisionPynqBoard(String boardId) async {
    provisionedPynqBoardIds.add(boardId);
    final boards = await fetchPynqBoards();
    return PynqBoardOperationResult(board: boards.first);
  }
}

class _RecordingStudioAkidaDeployController
    extends StudioAkidaDeployController {
  _RecordingStudioAkidaDeployController();

  String? lastSelectedHostId;
  int checkReadinessCalls = 0;
  int discoverLatestBundleCalls = 0;

  @override
  void selectHost(AkidaPairedHost? host) {
    lastSelectedHostId = host?.id;
    super.selectHost(host);
  }

  @override
  Future<void> checkReadiness(String spec) async {
    checkReadinessCalls += 1;
  }

  @override
  Future<void> discoverLatestBundle(String workspaceFolder) async {
    discoverLatestBundleCalls += 1;
  }

  @override
  Future<void> validate(String spec) async {}

  @override
  Future<void> installSelectedHost() async {}

  @override
  Future<void> deploySelectedHost(String spec) async {}
}

class _SyncingCanvasApiClient extends canvas_api.ApiClient {
  _SyncingCanvasApiClient() : super(baseUrl: 'http://test');

  @override
  Future<String> generateCnl(CanvasGraph graph) async {
    final node = graph.nodes.single;
    final name = node.parameters['name'];
    final count = node.parameters['n_neurons'];
    return 'The $name population MUST encode input using $count neurons';
  }

  @override
  Future<canonical_doc.ParseCnlResponse> canvasToCanonical(
    CanvasGraph graph,
  ) async {
    if (graph.nodes.isEmpty) {
      return const canonical_doc.ParseCnlResponse(
        document: canonical_doc.CanonicalEditorDocument(
          irJson: {},
          cnlText: '',
        ),
        diagnostics: [],
      );
    }
    final node = graph.nodes.first;
    final name = node.parameters['name'];
    final count = node.parameters['n_neurons'];
    final cnlText =
        'The $name population MUST encode input using $count neurons';
    return canonical_doc.ParseCnlResponse(
      document: canonical_doc.CanonicalEditorDocument(
        irJson: const {},
        cnlText: cnlText,
      ),
      diagnostics: const [],
    );
  }

  @override
  Future<canonical_doc.ParseCnlResponse> parseCnlCanonical(
    String specText,
  ) async {
    return canonical_doc.ParseCnlResponse(
      document: canonical_doc.CanonicalEditorDocument(
        irJson: const {},
        cnlText: specText,
      ),
      diagnostics: const [],
    );
  }

  @override
  Future<canvas_model.ValidationResult> validateGraph(CanvasGraph graph) async {
    return canvas_model.ValidationResult(valid: true, errors: const []);
  }
}

class _FailingCanonicalApiClient extends _SyncingCanvasApiClient {
  @override
  Future<canonical_doc.ParseCnlResponse> parseCnlCanonical(
    String specText,
  ) async {
    throw StateError('unsupported model');
  }
}

/// No-op PipelineController that prevents post-dispose async errors and
/// extra widget rebuilds from pipeline HTTP calls in unit tests.
///
/// The methods below must be real `@override`s. This class used to rely solely
/// on `noSuchMethod`, which never intercepts *concrete inherited* members — so
/// the override suppressed nothing, the real pipeline ran, and it published
/// state (arming workspace writes) and called the API on every test that
/// installed it.
class _NoOpPipelineController extends PipelineController {
  _NoOpPipelineController();

  @override
  PipelineState build() => const PipelineState();

  @override
  Future<void> runParseAndValidate(
    String spec, {
    String? backendOverride,
  }) async {}

  @override
  Future<void> runGenerateAndSimulate(
    String spec, {
    double duration = 1.0,
  }) async {}

  @override
  void hydrateCachedResultsForFile(WorkspaceFile? file) {}

  @override
  void cancelSimulation() {}

  @override
  void reset() {}
}

class _FakeScNeuroCoreTargetService extends ScNeuroCoreTargetService {
  Object? fetchError;

  @override
  Future<List<ScNeuroCoreTarget>> fetchTargets() async {
    if (fetchError != null) {
      // ignore: only_throw_errors
      throw fetchError!;
    }
    return const [
      ScNeuroCoreTarget(
        id: 'fpga-1',
        displayName: 'FPGA Z2 Dev Board',
        family: ScNeuroCoreFamily.xilinx,
        deviceSpec: 'xc7z020',
        toolchain: ScNeuroCoreToolchain.vivado,
        deploymentMode: ScNeuroCoreDeploymentMode.network,
        host: 'pynq-z2.local',
        sshPort: 22,
        username: 'xilinx',
      ),
    ];
  }
}
