import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/providers/pynq_deploy_provider.dart';
import 'package:neuro_toolkit/services/pynq_deploy_service.dart';

class MockPynqDeployService extends PynqDeployService {
  MockPynqDeployService({
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
        overlayVersion: '',
        state: PynqBoardState.ready,
        lastPreflightStatus: 'ok',
        lastPreflightMessage: 'Ready',
        lastRuntimeMode: 'hardware',
        hasPassword: true,
        sshKeyPath: '',
      ),
    ],
    this.exportResult,
    this.statusResponse,
    this.sitlResult,
    this.installOverlayResult,
    this.restartRuntimeResult,
    this.throwOnDeploy = false,
  });

  final List<PynqPairedBoard> boards;
  final PynqNetworkResponse? exportResult;
  final PynqDeployJob? statusResponse;
  final PynqSitlVerifyResult? sitlResult;
  final PynqOverlayInstallResult? installOverlayResult;
  final PynqRestartRuntimeResult? restartRuntimeResult;
  final bool throwOnDeploy;
  String? lastBoardId;
  PynqDeployPayload? lastDeployPayload;
  String? lastSavedHost;
  String? lastSavedRuntimeApiUrlOverride;
  Completer<PynqPairedBoard>? provisionCompleter;
  Completer<PynqPairedBoard>? installOverlayCompleter;

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
    lastSavedHost = host;
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
      state: PynqBoardState.unpaired,
      lastPreflightStatus: '',
      lastPreflightMessage: '',
      lastRuntimeMode: '',
      hasPassword: password.isNotEmpty ||
          (boards.isNotEmpty && boards.first.hasPassword),
      sshKeyPath: sshKeyPath,
    );
  }

  @override
  Future<PynqNetworkResponse> checkExportability({
    required String spec,
    required int weightBitWidth,
  }) async {
    if (spec == 'neurocnl offline') {
      throw PynqDeployException(
        error: 'NeuroCNL is not reachable at http://localhost:8000.',
        messages: <String>[
          'Start the CNL Studio / NeuroCNL service and retry Check Exportability.',
          'This step needs the NeuroCNL backend because it calls /api/deploy/pynq/network.',
        ],
      );
    }

    return exportResult ??
        const PynqNetworkResponse(
          supportState: PynqSupportState.exportable,
          warnings: <String>[],
          rejectionReasons: <String>[],
          deployPayload: PynqDeployPayload(
            weights: <double>[1.0, 2.0],
            config: PynqDeployConfig(
              threshold: 1.0,
              bitWidth: 8,
              scaleFactor: 127.0,
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
  Future<Map<String, dynamic>> deployToBoard({
    required String boardId,
    required PynqDeployPayload payload,
    String? bitstreamPathOverride,
  }) async {
    if (throwOnDeploy) {
      throw PynqDeployException(error: 'Deploy failed');
    }
    lastBoardId = boardId;
    lastDeployPayload = payload;
    return <String, dynamic>{'status': 'ok'};
  }

  @override
  Future<PynqDeployJob> getDeployStatus({
    required String boardId,
  }) async {
    return statusResponse ??
        const PynqDeployJob(status: PynqDeployJobStatus.configured);
  }

  @override
  Future<PynqPairedBoard> provisionBoard({
    required String boardId,
  }) async {
    if (provisionCompleter != null) {
      return provisionCompleter!.future;
    }
    return boards.first.copyWith(
      state: PynqBoardState.ready,
      lastPreflightStatus: 'ok',
      lastPreflightMessage: 'Ready',
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
    return installOverlayResult ??
        PynqOverlayInstallResult(
          board: boards.first.copyWith(
            state: PynqBoardState.ready,
            lastPreflightStatus: 'ok',
            lastPreflightMessage: 'Ready',
          ),
        );
  }

  @override
  Future<PynqRestartRuntimeResult> restartRuntime({
    required String boardId,
  }) async {
    return restartRuntimeResult ??
        PynqRestartRuntimeResult(
          board: boards.first.copyWith(
            state: PynqBoardState.ready,
            lastPreflightStatus: 'ok',
            lastPreflightMessage: 'Ready',
          ),
        );
  }

  @override
  Future<PynqSitlVerifyResult> runSitlVerification({
    required String boardId,
    List<double>? weights,
    Map<String, dynamic>? config,
  }) async {
    return sitlResult ??
        const PynqSitlVerifyResult(
          passed: true,
          totalCases: 1,
          passedCases: 1,
          meanExecUs: 40.0,
          maxExecUs: 50.0,
          summary: 'All 1 cases passed',
          steps: <PynqSitlStepResult>[],
        );
  }

  @override
  void dispose() {}
}

void main() {
  group('PynqDeployProvider', () {
    test('loads paired boards on construction', () async {
      final provider = PynqDeployProvider(service: MockPynqDeployService());
      await Future<void>.delayed(Duration.zero);

      expect(provider.pairedBoards, isNotEmpty);
      expect(provider.selectedBoard?.displayName, 'Desk PYNQ');
    });

    test('savePairedBoard follows host when runtime override is blank',
        () async {
      final service = MockPynqDeployService();
      final provider = PynqDeployProvider(service: service);
      await Future<void>.delayed(Duration.zero);

      await provider.savePairedBoard(
        boardId: 'board-1',
        displayName: 'Desk PYNQ',
        host: '192.168.2.53',
        sshPort: 22,
        username: 'xilinx',
        authMode: PynqBoardAuthMode.password,
        runtimeApiUrlOverride: '',
      );

      expect(service.lastSavedHost, '192.168.2.53');
      expect(service.lastSavedRuntimeApiUrlOverride, isEmpty);
      expect(provider.selectedBoard?.runtimeApiUrl, 'http://192.168.2.53:8002');
      expect(provider.selectedBoard?.runtimeApiUrlOverride, isEmpty);
    });

    test('savePairedBoard preserves explicit runtime override', () async {
      final service = MockPynqDeployService();
      final provider = PynqDeployProvider(service: service);
      await Future<void>.delayed(Duration.zero);

      await provider.savePairedBoard(
        boardId: 'board-1',
        displayName: 'Desk PYNQ',
        host: '192.168.2.53',
        sshPort: 22,
        username: 'xilinx',
        authMode: PynqBoardAuthMode.password,
        runtimeApiUrlOverride: 'http://192.168.2.99:8002',
      );

      expect(
          service.lastSavedRuntimeApiUrlOverride, 'http://192.168.2.99:8002');
      expect(provider.selectedBoard?.runtimeApiUrl, 'http://192.168.2.99:8002');
      expect(provider.selectedBoard?.runtimeApiUrlOverride,
          'http://192.168.2.99:8002');
    });

    test('checkExportability seeds deploy payload and override', () async {
      final provider = PynqDeployProvider(service: MockPynqDeployService());

      await provider.checkExportability(spec: 'test spec', weightBitWidth: 4);

      expect(provider.currentStep, PynqDeployStep.checked);
      expect(provider.deployPayload, isNotNull);
      expect(provider.bitstreamPathOverride, 'snn_overlay.bit');
    });

    test('checkExportability surfaces actionable NeuroCNL connection failure',
        () async {
      final provider = PynqDeployProvider(service: MockPynqDeployService());

      await provider.checkExportability(
        spec: 'neurocnl offline',
        weightBitWidth: 4,
      );

      expect(provider.currentStep, PynqDeployStep.error);
      expect(
        provider.errorMessage,
        contains('NeuroCNL is not reachable at http://localhost:8000.'),
      );
      expect(
        provider.errorMessage,
        contains('Start the CNL Studio / NeuroCNL service'),
      );
      expect(
        provider.errorMessage,
        contains('/api/deploy/pynq/network'),
      );
    });

    test('startDeploy uses selected paired board', () async {
      final service = MockPynqDeployService();
      final provider = PynqDeployProvider(service: service);
      await Future<void>.delayed(Duration.zero);
      await provider.checkExportability(spec: 'test spec', weightBitWidth: 4);

      await provider.startDeploy();

      expect(service.lastBoardId, 'board-1');
      expect(service.lastDeployPayload, isNotNull);
    });

    test('startDeploy fails when no paired board is selected', () async {
      final provider = PynqDeployProvider(
        service: MockPynqDeployService(boards: const <PynqPairedBoard>[]),
      );
      await Future<void>.delayed(Duration.zero);
      await provider.checkExportability(spec: 'test spec', weightBitWidth: 4);

      await provider.startDeploy();

      expect(provider.currentStep, PynqDeployStep.error);
      expect(provider.errorMessage, contains('Select a paired board'));
    });

    test('provisionSelectedBoard exposes in-progress feedback', () async {
      final service = MockPynqDeployService();
      final completer = Completer<PynqPairedBoard>();
      service.provisionCompleter = completer;
      final provider = PynqDeployProvider(service: service);
      await Future<void>.delayed(Duration.zero);

      final future = provider.provisionSelectedBoard();

      expect(provider.boardOperationInProgress, isTrue);
      expect(
        provider.activeBoardOperation,
        PynqBoardOperation.provisioningRuntime,
      );
      expect(
        provider.boardFeedbackMessage,
        contains('Provisioning runtime'),
      );
      expect(provider.selectedBoard?.state, PynqBoardState.provisioning);

      completer.complete(
        provider.selectedBoard!.copyWith(
          state: PynqBoardState.ready,
          lastPreflightStatus: 'ok',
          lastPreflightMessage: 'Ready',
        ),
      );
      await future;

      expect(provider.boardOperationInProgress, isFalse);
      expect(
        provider.boardFeedbackMessage,
        contains('Runtime provisioning finished'),
      );
      expect(provider.selectedBoard?.state, PynqBoardState.ready);
    });

    test(
        'provisionSelectedBoard points to overlay install when assets are missing',
        () async {
      final service = MockPynqDeployService();
      final completer = Completer<PynqPairedBoard>();
      service.provisionCompleter = completer;
      final provider = PynqDeployProvider(service: service);
      await Future<void>.delayed(Duration.zero);

      final future = provider.provisionSelectedBoard();

      completer.complete(
        provider.selectedBoard!.copyWith(
          state: PynqBoardState.overlayMissing,
          lastPreflightStatus: 'failed',
          lastPreflightMessage: 'Install Overlay next.',
        ),
      );
      await future;

      expect(provider.boardOperationInProgress, isFalse);
      expect(provider.boardFeedbackMessage,
          contains('install overlay assets next'));
      expect(provider.selectedBoard?.state, PynqBoardState.overlayMissing);
    });

    test(
        'installOverlayForSelectedBoard explains when the staged host package is missing',
        () async {
      final service = MockPynqDeployService(
        installOverlayResult: const PynqOverlayInstallResult(
          board: PynqPairedBoard(
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
        ),
      );
      final provider = PynqDeployProvider(service: service);
      await Future<void>.delayed(Duration.zero);

      await provider.installOverlayForSelectedBoard();

      expect(provider.boardOperationInProgress, isFalse);
      expect(
        provider.boardFeedbackMessage,
        contains('local staged overlay package is missing or incomplete'),
      );
      expect(provider.selectedBoard?.state, PynqBoardState.overlayMissing);
    });

    test(
        'installOverlayForSelectedBoard surfaces recovery guidance when runtime restart needs manual action',
        () async {
      final service = MockPynqDeployService(
        installOverlayResult: const PynqOverlayInstallResult(
          board: PynqPairedBoard(
            id: 'board-1',
            displayName: 'Desk PYNQ',
            host: '192.168.1.50',
            sshPort: 22,
            username: 'xilinx',
            authMode: PynqBoardAuthMode.password,
            credentialRef: '',
            runtimeApiUrl: 'http://192.168.1.50:8002',
            overlayVersion: '',
            state: PynqBoardState.degradedOptionalCapability,
            lastPreflightStatus: 'degraded',
            lastPreflightMessage:
                'Overlay files were uploaded, but the user-space runtime did not become healthy. Restart the board or run restart-runtime manually, then check readiness again.',
            lastRuntimeMode: 'hardware',
            hasPassword: true,
            sshKeyPath: '',
          ),
          warning: 'agent did not become healthy within 60s',
        ),
      );
      final provider = PynqDeployProvider(service: service);
      await Future<void>.delayed(Duration.zero);

      await provider.installOverlayForSelectedBoard();

      expect(provider.boardOperationInProgress, isFalse);
      expect(
        provider.boardFeedbackMessage,
        contains('Restart the board or run restart-runtime manually'),
      );
      expect(
        provider.errorMessage,
        isNull,
      );
      expect(
        provider.selectedBoard?.state,
        PynqBoardState.degradedOptionalCapability,
      );
    });

    test(
        'installOverlayForSelectedBoard keeps upload success distinct from preflight failure',
        () async {
      final service = MockPynqDeployService(
        installOverlayResult: const PynqOverlayInstallResult(
          board: PynqPairedBoard(
            id: 'board-1',
            displayName: 'Desk PYNQ',
            host: '192.168.1.50',
            sshPort: 22,
            username: 'xilinx',
            authMode: PynqBoardAuthMode.password,
            credentialRef: '',
            runtimeApiUrl: 'http://192.168.1.50:8002',
            overlayVersion: '',
            state: PynqBoardState.preflightFailed,
            lastPreflightStatus: 'failed',
            lastPreflightMessage: 'Runtime probe failed: No Devices Found.',
            lastRuntimeMode: 'hardware',
            hasPassword: true,
            sshKeyPath: '',
          ),
        ),
      );
      final provider = PynqDeployProvider(service: service);
      await Future<void>.delayed(Duration.zero);

      await provider.installOverlayForSelectedBoard();

      expect(provider.boardOperationInProgress, isFalse);
      expect(
        provider.boardFeedbackMessage,
        contains('Runtime probe failed: No Devices Found.'),
      );
      expect(provider.errorMessage, isNull);
      expect(provider.selectedBoard?.state, PynqBoardState.preflightFailed);
    });

    test('restartSelectedBoardRuntime surfaces manual recovery warning',
        () async {
      final service = MockPynqDeployService(
        restartRuntimeResult: const PynqRestartRuntimeResult(
          board: PynqPairedBoard(
            id: 'board-1',
            displayName: 'Desk PYNQ',
            host: '192.168.1.50',
            sshPort: 22,
            username: 'xilinx',
            authMode: PynqBoardAuthMode.password,
            credentialRef: '',
            runtimeApiUrl: 'http://192.168.1.50:8002',
            overlayVersion: '',
            state: PynqBoardState.degradedOptionalCapability,
            lastPreflightStatus: 'degraded',
            lastPreflightMessage:
                "Runtime is installed in user space. Enable passwordless sudo for 'xilinx', then re-run Provision Runtime to upgrade the board to systemd auto-start and launcher-managed restarts.",
            lastRuntimeMode: 'hardware',
            hasPassword: true,
            sshKeyPath: '',
          ),
          warning:
              "Runtime is installed in user space. Enable passwordless sudo for 'xilinx', then re-run Provision Runtime to upgrade the board to systemd auto-start and launcher-managed restarts.",
        ),
      );
      final provider = PynqDeployProvider(service: service);
      await Future<void>.delayed(Duration.zero);

      await provider.restartSelectedBoardRuntime();

      expect(provider.boardOperationInProgress, isFalse);
      expect(
        provider.boardFeedbackMessage,
        contains('Enable passwordless sudo'),
      );
      expect(
        provider.boardFeedbackMessage,
        contains('re-run Provision Runtime'),
      );
      expect(
        provider.boardFeedbackMessage,
        isNot(contains('Complete the restart manually on the board')),
      );
      expect(provider.errorMessage, isNull);
      expect(
        provider.selectedBoard?.state,
        PynqBoardState.degradedOptionalCapability,
      );
    });
  });
}
