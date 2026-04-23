import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/providers/pynq_deploy_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/pynq_deploy_screen.dart';
import 'package:neuro_toolkit/services/pynq_deploy_service.dart';

class _NopPynqDeployService extends PynqDeployService {
  _NopPynqDeployService({
    this.boards = const <PynqPairedBoard>[
      PynqPairedBoard(
        id: 'board-1',
        displayName: 'Desk PYNQ',
        host: '192.168.1.50',
        sshPort: 22,
        username: 'xilinx',
        authMode: PynqBoardAuthMode.password,
        credentialRef: '',
        runtimeApiUrl: 'http://192.168.1.50:8002',
        runtimeApiUrlOverride: '',
        overlayVersion: '',
        state: PynqBoardState.ready,
        lastPreflightStatus: 'ok',
        lastPreflightMessage: 'Ready',
        lastRuntimeMode: 'hardware',
        hasPassword: true,
        sshKeyPath: '',
      ),
    ],
  });

  final List<PynqPairedBoard> boards;
  Completer<PynqPairedBoard>? provisionCompleter;
  Completer<PynqPairedBoard>? installOverlayCompleter;
  String? lastSavedRuntimeApiUrlOverride;

  @override
  Future<List<PynqPairedBoard>> fetchPairedBoards() async => boards;

  @override
  Future<PynqPairedBoard> savePairedBoard({
    String? boardId,
    required String displayName,
    required String host,
    required int sshPort,
    required String username,
    required PynqBoardAuthMode authMode,
    String credentialRef = '',
    String password = '',
    String sshKeyPath = '',
    String runtimeApiUrlOverride = '',
    String overlayVersion = '',
  }) async {
    lastSavedRuntimeApiUrlOverride = runtimeApiUrlOverride;
    final effectiveRuntimeApiUrl = runtimeApiUrlOverride.isNotEmpty
        ? runtimeApiUrlOverride
        : 'http://$host:8002';
    return PynqPairedBoard(
      id: boardId ?? 'board-1',
      displayName: displayName,
      host: host,
      sshPort: sshPort,
      username: username,
      authMode: authMode,
      credentialRef: credentialRef,
      runtimeApiUrl: effectiveRuntimeApiUrl,
      runtimeApiUrlOverride: runtimeApiUrlOverride,
      overlayVersion: overlayVersion,
      state: PynqBoardState.ready,
      lastPreflightStatus: 'ok',
      lastPreflightMessage: 'Ready',
      lastRuntimeMode: 'hardware',
      hasPassword: true,
      sshKeyPath: sshKeyPath,
    );
  }

  @override
  Future<PynqNetworkResponse> checkExportability({
    required String spec,
    required int weightBitWidth,
  }) async {
    return const PynqNetworkResponse(
      supportState: PynqSupportState.exportable,
      warnings: <String>[],
      rejectionReasons: <String>[],
      deployPayload: PynqDeployPayload(
        weights: <double>[1.0, 2.0],
        config: PynqDeployConfig(
          threshold: 1.0,
          bitWidth: 4,
          scaleFactor: 7.0,
        ),
        bitstreamPath: 'snn_overlay.bit',
        registerMap: PynqRegisterMap(
          baseAddress: 0x40000000,
          controlRegOffset: 0x00,
          statusRegOffset: 0x04,
          neuronBaseOffset: 0x100,
          weightBaseOffset: 0x1000,
          dmaChannel: 'axi_dma_0',
          inputBufferAddr: 0,
          outputBufferAddr: 0,
          timestepUs: 1000,
        ),
      ),
    );
  }

  @override
  Future<PynqPairedBoard> provisionBoard({
    required String boardId,
  }) async {
    if (provisionCompleter != null) {
      return provisionCompleter!.future;
    }
    return const PynqPairedBoard(
      id: 'board-1',
      displayName: 'Desk PYNQ',
      host: '192.168.1.50',
      sshPort: 22,
      username: 'xilinx',
      authMode: PynqBoardAuthMode.password,
      credentialRef: '',
      runtimeApiUrl: 'http://192.168.1.50:8002',
      runtimeApiUrlOverride: '',
      overlayVersion: '',
      state: PynqBoardState.ready,
      lastPreflightStatus: 'ok',
      lastPreflightMessage: 'Ready',
      lastRuntimeMode: 'hardware',
      hasPassword: true,
      sshKeyPath: '',
    );
  }

  @override
  Future<PynqOverlayInstallResult> installOverlay({
    required String boardId,
  }) async {
    if (installOverlayCompleter != null) {
      return PynqOverlayInstallResult(
          board: await installOverlayCompleter!.future);
    }
    return const PynqOverlayInstallResult(
      board: PynqPairedBoard(
        id: 'board-1',
        displayName: 'Desk PYNQ',
        host: '192.168.1.50',
        sshPort: 22,
        username: 'xilinx',
        authMode: PynqBoardAuthMode.password,
        credentialRef: '',
        runtimeApiUrl: 'http://192.168.1.50:8002',
        runtimeApiUrlOverride: '',
        overlayVersion: '',
        state: PynqBoardState.ready,
        lastPreflightStatus: 'ok',
        lastPreflightMessage: 'Ready',
        lastRuntimeMode: 'hardware',
        hasPassword: true,
        sshKeyPath: '',
      ),
    );
  }

  @override
  void dispose() {}
}

Widget _buildTestApp(PynqDeployProvider provider) {
  return MaterialApp(
    home: ProviderScope(
      overrides: [
        pynqDeployStateProvider.overrideWith((ref) => provider),
      ],
      child: const PynqDeployScreen(),
    ),
  );
}

void main() {
  group('PynqDeployScreen', () {
    testWidgets('renders stepper and paired board controls', (tester) async {
      final provider = PynqDeployProvider(service: _NopPynqDeployService());
      await tester.pumpWidget(_buildTestApp(provider));
      await tester.pump();

      expect(find.text('Prepare'), findsOneWidget);
      expect(find.text('Deploy'), findsOneWidget);
      expect(find.text('Paired Board'), findsOneWidget);
      expect(find.text('Provision Runtime'), findsOneWidget);
      expect(find.text('Check Readiness'), findsOneWidget);
      expect(find.text('Deploy to PYNQ'), findsWidgets);
      expect(
        find.textContaining('Run Check Exportability first'),
        findsOneWidget,
      );
      expect(
        find.textContaining('What to expect after pressing Deploy'),
        findsOneWidget,
      );
    });

    testWidgets('loads runtime API URL override into the pairing form',
        (tester) async {
      final provider = PynqDeployProvider(
        service: _NopPynqDeployService(
          boards: const <PynqPairedBoard>[
            PynqPairedBoard(
              id: 'board-1',
              displayName: 'Desk PYNQ',
              host: '192.168.1.50',
              sshPort: 22,
              username: 'xilinx',
              authMode: PynqBoardAuthMode.password,
              credentialRef: '',
              runtimeApiUrl: 'http://192.168.2.99:8002',
              runtimeApiUrlOverride: 'http://192.168.2.99:8002',
              overlayVersion: '',
              state: PynqBoardState.ready,
              lastPreflightStatus: 'ok',
              lastPreflightMessage: 'Ready',
              lastRuntimeMode: 'hardware',
              hasPassword: true,
              sshKeyPath: '',
            ),
          ],
        ),
      );
      await tester.pumpWidget(_buildTestApp(provider));
      await tester.pump();

      expect(find.text('Runtime API URL override (optional)'), findsOneWidget);
      expect(
          find.text('Leave blank to use http://<host>:8002'), findsOneWidget);
      expect(find.text('http://192.168.2.99:8002'), findsWidgets);
    });

    testWidgets(
        'editing host with blank override updates displayed runtime URL',
        (tester) async {
      final service = _NopPynqDeployService();
      final provider = PynqDeployProvider(service: service);
      await tester.pumpWidget(_buildTestApp(provider));
      await tester.pump();

      expect(find.text('Runtime: http://192.168.1.50:8002'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(2), '192.168.2.53');
      await tester.enterText(find.byType(TextField).at(6), '');
      await tester.ensureVisible(find.text('Save Pairing'));
      await tester.tap(find.text('Save Pairing'));
      await tester.pumpAndSettle();

      expect(service.lastSavedRuntimeApiUrlOverride, isEmpty);
      expect(find.text('Runtime: http://192.168.2.53:8002'), findsOneWidget);
    });

    testWidgets('shows deployment package after exportability check',
        (tester) async {
      final provider = PynqDeployProvider(service: _NopPynqDeployService());
      await tester.pumpWidget(_buildTestApp(provider));
      await tester.pump();

      await provider.checkExportability(
        spec: 'The sensory neuron MUST fire.',
        weightBitWidth: 4,
      );
      await tester.pump();

      expect(find.text('Deployment Package'), findsOneWidget);
      expect(find.textContaining('2 packed weights'), findsOneWidget);
      expect(find.text('Deploy to PYNQ'), findsWidgets);
      expect(
        find.textContaining(
          'Press Deploy to PYNQ to send the validated weights and runtime configuration to Desk PYNQ.',
        ),
        findsOneWidget,
      );
      expect(find.text('Deploy to PYNQ'), findsWidgets);
    });

    testWidgets('shows board activity feedback while provisioning',
        (tester) async {
      final service = _NopPynqDeployService();
      final completer = Completer<PynqPairedBoard>();
      service.provisionCompleter = completer;
      final provider = PynqDeployProvider(service: service);
      await tester.pumpWidget(_buildTestApp(provider));
      await tester.pump();

      await tester.ensureVisible(find.text('Provision Runtime'));
      await tester.tap(find.text('Provision Runtime'));
      await tester.pump();

      expect(find.textContaining('Provisioning runtime'), findsWidgets);
      expect(find.text('Provisioning...'), findsOneWidget);

      completer.complete(
        const PynqPairedBoard(
          id: 'board-1',
          displayName: 'Desk PYNQ',
          host: '192.168.1.50',
          sshPort: 22,
          username: 'xilinx',
          authMode: PynqBoardAuthMode.password,
          credentialRef: '',
          runtimeApiUrl: 'http://192.168.1.50:8002',
          overlayVersion: '',
          state: PynqBoardState.ready,
          lastPreflightStatus: 'ok',
          lastPreflightMessage: 'Ready',
          lastRuntimeMode: 'hardware',
          hasPassword: true,
          sshKeyPath: '',
        ),
      );
      await tester.pump();

      expect(
          find.textContaining('Runtime provisioning finished'), findsWidgets);
    });

    testWidgets(
        'shows overlay-install guidance after provisioning completes without assets',
        (tester) async {
      final service = _NopPynqDeployService();
      final completer = Completer<PynqPairedBoard>();
      service.provisionCompleter = completer;
      final provider = PynqDeployProvider(service: service);
      await tester.pumpWidget(_buildTestApp(provider));
      await tester.pump();

      await tester.ensureVisible(find.text('Provision Runtime'));
      await tester.tap(find.text('Provision Runtime'));
      await tester.pump();

      completer.complete(
        const PynqPairedBoard(
          id: 'board-1',
          displayName: 'Desk PYNQ',
          host: '192.168.1.50',
          sshPort: 22,
          username: 'xilinx',
          authMode: PynqBoardAuthMode.password,
          credentialRef: '',
          runtimeApiUrl: 'http://192.168.1.50:8002',
          overlayVersion: '',
          state: PynqBoardState.overlayMissing,
          lastPreflightStatus: 'failed',
          lastPreflightMessage: 'Install Overlay next.',
          lastRuntimeMode: 'hardware',
          hasPassword: true,
          sshKeyPath: '',
        ),
      );
      await tester.pump();

      expect(find.textContaining('install overlay assets next'), findsWidgets);
      expect(find.text('State: Overlay Missing'), findsOneWidget);
    });

    testWidgets(
        'shows staged-overlay guidance when install overlay cannot start',
        (tester) async {
      final service = _NopPynqDeployService();
      final completer = Completer<PynqPairedBoard>();
      service.installOverlayCompleter = completer;
      final provider = PynqDeployProvider(service: service);
      await tester.pumpWidget(_buildTestApp(provider));
      await tester.pump();

      await tester.ensureVisible(find.text('Install Overlay'));
      await tester.tap(find.text('Install Overlay'));
      await tester.pump();

      completer.complete(
        const PynqPairedBoard(
          id: 'board-1',
          displayName: 'Desk PYNQ',
          host: '192.168.1.50',
          sshPort: 22,
          username: 'xilinx',
          authMode: PynqBoardAuthMode.password,
          credentialRef: '',
          runtimeApiUrl: 'http://192.168.1.50:8002',
          overlayVersion: '',
          state: PynqBoardState.overlayMissing,
          lastPreflightStatus: 'failed',
          lastPreflightMessage: 'Stage overlay assets locally first.',
          lastRuntimeMode: 'hardware',
          hasPassword: true,
          sshKeyPath: '',
        ),
      );
      await tester.pump();

      expect(
        find.textContaining(
          'local staged overlay package is missing or incomplete',
        ),
        findsWidgets,
      );
      expect(find.text('State: Overlay Missing'), findsOneWidget);
    });
  });
}
