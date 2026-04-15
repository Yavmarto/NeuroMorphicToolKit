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
    this.throwOnDeploy = false,
  });

  final List<PynqPairedBoard> boards;
  final PynqNetworkResponse? exportResult;
  final PynqDeployJob? statusResponse;
  final PynqSitlVerifyResult? sitlResult;
  final bool throwOnDeploy;
  String? lastBoardId;
  PynqDeployPayload? lastDeployPayload;
  Completer<PynqPairedBoard>? provisionCompleter;

  @override
  Future<List<PynqPairedBoard>> fetchPairedBoards() async => boards;

  @override
  Future<PynqNetworkResponse> checkExportability({
    required String spec,
    required int weightBitWidth,
  }) async {
    return exportResult ??
        const PynqNetworkResponse(
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
              weightBaseOffset: 0x10000,
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

    test('checkExportability seeds deploy payload and override', () async {
      final provider = PynqDeployProvider(service: MockPynqDeployService());

      await provider.checkExportability(spec: 'test spec', weightBitWidth: 4);

      expect(provider.currentStep, PynqDeployStep.checked);
      expect(provider.deployPayload, isNotNull);
      expect(provider.bitstreamPathOverride, 'snn_overlay.bit');
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
  });
}
