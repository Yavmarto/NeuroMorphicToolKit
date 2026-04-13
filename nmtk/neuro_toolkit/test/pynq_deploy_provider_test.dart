import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/providers/pynq_deploy_provider.dart';
import 'package:neuro_toolkit/services/pynq_deploy_service.dart';

// ---------------------------------------------------------------------------
// Mock service
// ---------------------------------------------------------------------------

class MockPynqDeployService extends PynqDeployService {
  MockPynqDeployService({
    this.exportResult,
    this.deployResponse,
    this.statusResponse,
    this.sitlResult,
    this.throwOnExportability = false,
    this.throwOnDeploy = false,
    this.throwOnVerify = false,
  });

  final PynqNetworkResponse? exportResult;
  final Map<String, dynamic>? deployResponse;
  final PynqDeployJob? statusResponse;
  final PynqSitlVerifyResult? sitlResult;
  final bool throwOnExportability;
  final bool throwOnDeploy;
  final bool throwOnVerify;
  PynqDeployPayload? lastDeployPayload;
  String? lastBitstreamPathOverride;

  @override
  Future<PynqNetworkResponse> checkExportability({
    required String spec,
    required int weightBitWidth,
  }) async {
    if (throwOnExportability) {
      throw PynqDeployException(error: 'parse_failed', messages: ['bad spec']);
    }
    return exportResult ??
        const PynqNetworkResponse(
          supportState: PynqSupportState.exportable,
          warnings: [],
          rejectionReasons: [],
          deployPayload: PynqDeployPayload(
            weights: [1.0, 2.0],
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
    required String boardBaseUrl,
    required PynqDeployPayload payload,
    String? apiKey,
    String? bitstreamPathOverride,
  }) async {
    if (throwOnDeploy) {
      throw PynqDeployException(
        error: 'Deploy failed',
        messages: ['board unreachable'],
      );
    }
    lastDeployPayload = payload;
    lastBitstreamPathOverride = bitstreamPathOverride;
    return deployResponse ?? {'status': 'success'};
  }

  @override
  Future<PynqDeployJob> getDeployStatus({
    required String boardBaseUrl,
    String? apiKey,
  }) async {
    return statusResponse ??
        const PynqDeployJob(status: PynqDeployJobStatus.configured);
  }

  @override
  Future<PynqSitlVerifyResult> runSitlVerification({
    required String boardBaseUrl,
    String? apiKey,
    List<double>? weights,
    Map<String, dynamic>? config,
  }) async {
    if (throwOnVerify) {
      throw PynqDeployException(error: 'verification_failed');
    }
    return sitlResult ??
        const PynqSitlVerifyResult(
          passed: true,
          totalCases: 1,
          passedCases: 1,
          meanExecUs: 40.0,
          maxExecUs: 50.0,
          summary: 'All 1 cases passed',
          steps: [],
        );
  }

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PynqDeployProvider', () {
    test('initial state is idle', () {
      final provider = PynqDeployProvider(service: MockPynqDeployService());
      expect(provider.currentStep, PynqDeployStep.idle);
      expect(provider.exportResult, isNull);
      expect(provider.errorMessage, isNull);
    });

    test('initial boardBaseUrl is empty', () {
      final provider = PynqDeployProvider(service: MockPynqDeployService());
      expect(provider.boardBaseUrl, isEmpty);
    });

    test('checkExportability transitions idle → checking → checked', () async {
      final provider = PynqDeployProvider(service: MockPynqDeployService());

      final steps = <PynqDeployStep>[];
      provider.addListener(() => steps.add(provider.currentStep));

      await provider.checkExportability(spec: 'test spec', weightBitWidth: 4);

      expect(steps, [PynqDeployStep.checking, PynqDeployStep.checked]);
      expect(provider.exportResult, isNotNull);
      expect(
        provider.exportResult!.supportState,
        PynqSupportState.exportable,
      );
    });

    test('checkExportability transitions to error on exception', () async {
      final provider = PynqDeployProvider(
        service: MockPynqDeployService(throwOnExportability: true),
      );

      await provider.checkExportability(spec: 'bad', weightBitWidth: 4);

      expect(provider.currentStep, PynqDeployStep.error);
      expect(provider.errorMessage, contains('parse_failed'));
    });

    test('startDeploy transitions checked → deploying → polling', () async {
      final provider = PynqDeployProvider(service: MockPynqDeployService());
      provider.setRunSitl(false);
      provider.setBoardBaseUrl('http://10.0.0.1:8002');
      await provider.checkExportability(spec: 'test spec', weightBitWidth: 4);

      final steps = <PynqDeployStep>[];
      provider.addListener(() => steps.add(provider.currentStep));

      await provider.startDeploy();

      // polling is started asynchronously; we just check deploying was seen
      expect(steps, contains(PynqDeployStep.deploying));
      expect(steps, contains(PynqDeployStep.polling));
    });

    test('startDeploy transitions to error when deploy throws', () async {
      final provider = PynqDeployProvider(
        service: MockPynqDeployService(throwOnDeploy: true),
      );
      provider.setBoardBaseUrl('http://10.0.0.1:8002');
      await provider.checkExportability(spec: 'test spec', weightBitWidth: 4);

      await provider.startDeploy();

      expect(provider.currentStep, PynqDeployStep.error);
      expect(provider.errorMessage, contains('Deploy failed'));
    });

    test('startDeploy uses validated payload and bitstream override', () async {
      final service = MockPynqDeployService();
      final provider = PynqDeployProvider(service: service);
      provider.setBoardBaseUrl('http://10.0.0.1:8002');
      await provider.checkExportability(spec: 'test spec', weightBitWidth: 4);
      provider.setBitstreamPathOverride('/opt/overlays/custom.bit');

      await provider.startDeploy();

      expect(service.lastDeployPayload, isNotNull);
      expect(service.lastDeployPayload!.weightCount, 2);
      expect(service.lastBitstreamPathOverride, '/opt/overlays/custom.bit');
    });

    test('startDeploy requires board URL', () async {
      final provider = PynqDeployProvider(service: MockPynqDeployService());
      await provider.checkExportability(spec: 'test spec', weightBitWidth: 4);

      await provider.startDeploy();

      expect(provider.currentStep, PynqDeployStep.error);
      expect(provider.errorMessage, contains('Board endpoint URL is required'));
    });

    test('setBoardBaseUrl updates the URL', () {
      final provider = PynqDeployProvider(service: MockPynqDeployService());
      provider.setBoardBaseUrl('http://10.0.0.1:8002');
      expect(provider.boardBaseUrl, 'http://10.0.0.1:8002');
    });

    test('setBoardApiKey updates the key', () {
      final provider = PynqDeployProvider(service: MockPynqDeployService());
      provider.setBoardApiKey('secret-key');
      expect(provider.boardApiKey, 'secret-key');
    });

    test('checkExportability seeds bitstream path override from payload',
        () async {
      final provider = PynqDeployProvider(service: MockPynqDeployService());

      await provider.checkExportability(spec: 'test spec', weightBitWidth: 4);

      expect(provider.bitstreamPathOverride, 'snn_overlay.bit');
    });

    test('setRunSitl toggles flag', () {
      final provider = PynqDeployProvider(service: MockPynqDeployService());
      expect(provider.runSitl, isFalse);
      provider.setRunSitl(true);
      expect(provider.runSitl, isTrue);
    });

    test('runVerification populates sitlResult on success', () async {
      final provider = PynqDeployProvider(service: MockPynqDeployService());

      await provider.runVerification();

      expect(provider.currentStep, PynqDeployStep.done);
      expect(provider.sitlResult, isNotNull);
      expect(provider.sitlResult!.passed, isTrue);
    });

    test('runVerification transitions to error when service throws', () async {
      final provider = PynqDeployProvider(
        service: MockPynqDeployService(throwOnVerify: true),
      );

      await provider.runVerification();

      expect(provider.currentStep, PynqDeployStep.error);
      expect(provider.errorMessage, isNotNull);
    });

    test('reset clears all state', () async {
      final provider = PynqDeployProvider(service: MockPynqDeployService());
      await provider.checkExportability(spec: 'test', weightBitWidth: 4);

      provider.reset();

      expect(provider.currentStep, PynqDeployStep.idle);
      expect(provider.exportResult, isNull);
      expect(provider.deployJob, isNull);
      expect(provider.sitlResult, isNull);
      expect(provider.errorMessage, isNull);
    });
  });
}
