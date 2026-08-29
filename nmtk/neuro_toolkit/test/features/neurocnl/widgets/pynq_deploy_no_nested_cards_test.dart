// The PYNQ-Z2 deploy workspace is FLAT — no NmtkSurfaceCard frame inside the
// NmtkSection, no ChoiceChip rows. Sibling of
// `deploy_workspace_no_section_card_test.dart` (Akida) and
// `sc_neurocore_lava_workspace_no_section_card_test.dart`, which has referenced
// this file since before it existed.
//
// Also covers the shape of the workspace itself: PYNQ used to route to a
// verdict-only panel with a single "Run PYNQ Check" button, so these assertions
// are what stops it regressing to that.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/hardware_reachability_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_pynq_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/studio_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

import '../providers_test.mocks.dart';

const _kSectionTitle = 'PYNQ-Z2 Overlay';

PynqPairedBoard _board({
  PynqBoardState state = PynqBoardState.ready,
  String overlayVersion = '1.0.1',
}) {
  return PynqPairedBoard(
    id: 'board-1',
    displayName: 'Bench PYNQ-Z2',
    host: '192.168.2.99',
    sshPort: 22,
    username: 'xilinx',
    authMode: PynqBoardAuthMode.password,
    credentialRef: '',
    runtimeApiUrl: 'http://192.168.2.99:8002',
    overlayVersion: overlayVersion,
    state: state,
    lastPreflightStatus: 'ok',
    lastPreflightMessage: 'Overlay assets present.',
    lastRuntimeMode: 'hardware',
    hasPassword: true,
    sshKeyPath: '',
  );
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
    // The workspace validates on its first frame. Stub the verdict so the pane
    // renders its real states instead of the "checking…" placeholder; no
    // `trained_weights` key is the untrained case, which is the default the
    // provenance badge has to call out.
    when(
      mockApi.getPynqDeployability(
        any,
        bitWidth: anyNamed('bitWidth'),
        trainedNirBase64: anyNamed('trainedNirBase64'),
      ),
    ).thenAnswer(
      (_) async => <String, dynamic>{
        'support_state': 'exportable',
        'warnings': <String>[],
        'rejections': <String>[],
        'network_summary': <String, dynamic>{
          'n_neurons': 36,
          'n_synapses': 128,
        },
      },
    );
    // No trained NIR in the workspace — a 404 from this endpoint is the normal
    // state for an untrained network, not a failure.
    when(mockApi.latestTrainedNir(any)).thenThrow(Exception('404'));
  });

  Future<void> pumpPynqWorkspace(
    WidgetTester tester, {
    PynqPairedBoard? board,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          // The workspace resolves its board from this when nothing has been
          // selected in-session, and it would otherwise hit launcher control.
          pynqBoardReadinessProvider.overrideWith((ref) async => board),
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(StudioScreen)),
    );
    container.read(workspaceProvider.notifier)
      ..togglePlatform('pynq')
      ..setActivePipelineStep('deployHardware');
    await tester.pumpAndSettle();

    final restoreDialog = find.text('Restore previous session?');
    if (restoreDialog.evaluate().isNotEmpty) {
      await tester.tap(find.text('Start fresh'));
      await tester.pumpAndSettle();
    }

    final configure = find.byKey(const Key('hardware-target-open-pynq'));
    if (configure.evaluate().isNotEmpty) {
      await tester.tap(configure);
      await tester.pumpAndSettle();
    }
  }

  Finder sectionFinder() => find.byWidgetPredicate(
    (widget) => widget is NmtkSection && widget.title == _kSectionTitle,
    description: 'NmtkSection(title: $_kSectionTitle)',
  );

  group('PYNQ-Z2 deploy workspace', () {
    testWidgets('uses NmtkSection', (WidgetTester tester) async {
      await pumpPynqWorkspace(tester, board: _board());

      expect(sectionFinder(), findsOneWidget);
    });

    testWidgets('has no NmtkSurfaceCard or ChoiceChip descendants', (
      WidgetTester tester,
    ) async {
      await pumpPynqWorkspace(tester, board: _board());

      final section = sectionFinder();
      expect(section, findsOneWidget);
      expect(
        find.descendant(of: section, matching: find.byType(NmtkSurfaceCard)),
        findsNothing,
      );
      expect(
        find.descendant(of: section, matching: find.byType(ChoiceChip)),
        findsNothing,
        reason:
            'The bit-width picker moved off ChoiceChip rows with the rest of '
            'the deploy workspaces.',
      );
    });

    testWidgets('offers pairing when no board is paired', (
      WidgetTester tester,
    ) async {
      await pumpPynqWorkspace(tester, board: null);

      expect(find.byKey(const Key('pynq-pair-board')), findsOneWidget);
      expect(find.text('No PYNQ-Z2 board is paired.'), findsOneWidget);
    });

    testWidgets('a ready board offers deploy, not just a verdict check', (
      WidgetTester tester,
    ) async {
      await pumpPynqWorkspace(tester, board: _board());

      expect(find.byKey(const Key('pynq-deploy-network')), findsOneWidget);
      expect(find.byKey(const Key('pynq-check-readiness')), findsOneWidget);
      // Neither setup step is offered on a board that is already ready.
      expect(find.byKey(const Key('pynq-provision-board')), findsNothing);
      expect(find.byKey(const Key('pynq-install-overlay')), findsNothing);
    });

    testWidgets('a board with no overlay is offered Install Overlay', (
      WidgetTester tester,
    ) async {
      await pumpPynqWorkspace(
        tester,
        board: _board(state: PynqBoardState.overlayMissing, overlayVersion: ''),
      );

      expect(find.byKey(const Key('pynq-install-overlay')), findsOneWidget);
      expect(find.text('Overlay Missing'), findsOneWidget);
    });

    testWidgets(
      'a user-space board with no overlay is offered Install Overlay',
      (WidgetTester tester) async {
        await pumpPynqWorkspace(
          tester,
          board: _board(
            state: PynqBoardState.degradedOptionalCapability,
            overlayVersion: '',
          ),
        );

        expect(find.byKey(const Key('pynq-install-overlay')), findsOneWidget);
      },
    );

    testWidgets('a freshly reachable board is offered the runtime install', (
      WidgetTester tester,
    ) async {
      await pumpPynqWorkspace(
        tester,
        board: _board(state: PynqBoardState.reachable, overlayVersion: ''),
      );

      expect(find.byKey(const Key('pynq-provision-board')), findsOneWidget);
      expect(find.byKey(const Key('pynq-install-overlay')), findsNothing);
    });

    testWidgets('run controls stay hidden until a deploy has happened', (
      WidgetTester tester,
    ) async {
      await pumpPynqWorkspace(tester, board: _board());

      // Without a deploy ack the board holds no configured network, so running
      // would fail on the board with "Overlay not deployed".
      expect(find.byKey(const Key('pynq-run-network')), findsNothing);
      expect(find.byKey(const Key('pynq-input-spikes')), findsNothing);
    });
  });

  group('trained-weight provenance', () {
    // A zero-weight deploy is indistinguishable from a working one everywhere
    // else: it succeeds, reports runtime_mode hardware, and produces no spikes.
    // The pane has to say which it is before the user reads a green result as a
    // working model.
    testWidgets('an untrained workspace is called out as untrained', (
      WidgetTester tester,
    ) async {
      await pumpPynqWorkspace(tester, board: _board());

      expect(find.text('Untrained weights'), findsOneWidget);
      expect(
        find.textContaining('all-zero weight matrix'),
        findsOneWidget,
        reason:
            'The reason the board will fire nothing has to be stated, not left '
            'to be inferred from an empty result later.',
      );
    });

    test('hasTrainedWeights needs weights that are actually non-zero', () {
      PynqNetworkResponse withStatus(PynqTrainedWeightStatus? status) {
        return PynqNetworkResponse(
          supportState: PynqSupportState.exportable,
          warnings: const <String>[],
          rejectionReasons: const <String>[],
          trainedWeights: status,
        );
      }

      // No trained NIR supplied at all.
      expect(
        StudioPynqDeployState(exportResult: withStatus(null)).hasTrainedWeights,
        isFalse,
      );
      // A model exported before training ran: matches the shape, all zeros.
      expect(
        StudioPynqDeployState(
          exportResult: withStatus(
            const PynqTrainedWeightStatus(
              applied: true,
              nonzero: 0,
              detail: 'every weight in it is zero',
            ),
          ),
        ).hasTrainedWeights,
        isFalse,
      );
      expect(
        StudioPynqDeployState(
          exportResult: withStatus(
            const PynqTrainedWeightStatus(
              applied: true,
              nonzero: 128,
              detail: 'Loaded trained weights from fc',
            ),
          ),
        ).hasTrainedWeights,
        isTrue,
      );
    });
  });

  group('StudioPynqDeployState gates', () {
    test('canDeploy needs both a payload and a ready board', () {
      const payload = PynqDeployPayload(
        weights: <double>[1, 2, 3],
        config: PynqDeployConfig(threshold: 1, bitWidth: 8, scaleFactor: 1),
        bitstreamPath: 'snn_overlay.bit',
        // A slice of the overlay-v2 map from `Neurochip/hardware/pynq_z2/
        // overlay_manifest.json` — the gate under test never reads it, but a
        // made-up map would be a confusing fixture to copy from.
        registerMap: PynqRegisterMap(<String, dynamic>{
          'base_address': 0x40000000,
          'dma_channel': 'axi_dma_0',
          'timestep_us': 1000,
        }),
      );
      const exportable = PynqNetworkResponse(
        supportState: PynqSupportState.exportable,
        warnings: <String>[],
        rejectionReasons: <String>[],
        deployPayload: payload,
      );

      // Payload but no board.
      expect(
        const StudioPynqDeployState(exportResult: exportable).canDeploy,
        isFalse,
      );
      // Board but no payload.
      expect(StudioPynqDeployState(selectedBoard: _board()).canDeploy, isFalse);
      // A board that has not passed preflight cannot take a deploy.
      expect(
        StudioPynqDeployState(
          exportResult: exportable,
          selectedBoard: _board(state: PynqBoardState.overlayMissing),
        ).canDeploy,
        isFalse,
      );
      expect(
        StudioPynqDeployState(
          exportResult: exportable,
          selectedBoard: _board(),
        ).canDeploy,
        isTrue,
      );
    });

    test('input spikes tolerate the separators users actually paste', () {
      const state = StudioPynqDeployState(inputSpikesText: '0, 3\n7  11,');
      expect(state.inputSpikes, <int>[0, 3, 7, 11]);
    });

    test('empty or unparseable spike text yields no spikes', () {
      expect(
        const StudioPynqDeployState(inputSpikesText: '').inputSpikes,
        isEmpty,
      );
      expect(
        const StudioPynqDeployState(inputSpikesText: 'none').inputSpikes,
        isEmpty,
      );
    });
  });
}
