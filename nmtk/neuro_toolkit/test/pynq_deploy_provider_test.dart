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
            weights: [1.0],
            config: {'bit_width': 4},
          ),
        );
  }

  @override
  Future<Map<String, dynamic>> deployToBoard({
    required String boardBaseUrl,
    required List<double> weights,
    required Map<String, dynamic> config,
    String? bitstreamPath,
    Map<String, dynamic>? registerMap,
    String? apiKey,
  }) async {
    if (throwOnDeploy) {
      throw PynqDeployException(
        error: 'Deploy failed',
        messages: ['board unreachable'],
      );
    }
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

      final steps = <PynqDeployStep>[];
      provider.addListener(() => steps.add(provider.currentStep));

      await provider.startDeploy(weights: [], config: {});

      // polling is started asynchronously; we just check deploying was seen
      expect(steps, contains(PynqDeployStep.deploying));
      expect(steps, contains(PynqDeployStep.polling));
    });

    test('startDeploy transitions to error when deploy throws', () async {
      final provider = PynqDeployProvider(
        service: MockPynqDeployService(throwOnDeploy: true),
      );

      await provider.startDeploy(weights: [], config: {});

      expect(provider.currentStep, PynqDeployStep.error);
      expect(provider.errorMessage, contains('Deploy failed'));
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
