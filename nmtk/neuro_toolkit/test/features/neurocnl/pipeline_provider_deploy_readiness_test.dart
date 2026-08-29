/// Tests for the deploy-readiness auto-trigger added to
/// [PipelineController.runParseAndValidate] (Task 4 of
/// `current tasks/2026-07-04/validation-deploy-readiness/`).
///
/// After a passing validate, the pipeline now auto-calls either
/// `apiClient.previewDeployTarget` (hardware/codegen targets) or
/// `simulatorPreflightControllerProvider.notifier.runPreflight` (simulator
/// targets) and mirrors the outcome into `PipelineState.deployReadiness*`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/deploy_preview_result.dart';
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/simulator_preflight.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart' show ApiException;
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/deploy_readiness_result.dart';

import 'providers_test.mocks.dart';

const _testSpec = 'MUST fire ONLY IF membrane potential exceeds 1.5';

const _parseResult = ParseResult(sentences: [], total: 0, errors: 0);
const _passingValidateResult = ValidationResult(
  layer1: Layer1Result(overall: true, passed: [], failed: []),
  layer2: Layer2Result(
    overall: true,
    checksPassed: [],
    checksFailed: [],
    neuronsFound: [],
  ),
  overall: true,
  backendSupport: BackendSupportResult(backend: 'nir', verdict: 'faithful'),
);
const _failingValidateResult = ValidationResult(
  layer1: Layer1Result(
    overall: false,
    passed: [],
    failed: [
      InvariantResult(
        name: 'some_invariant',
        description: 'some invariant',
        result: false,
      ),
    ],
  ),
  layer2: Layer2Result(
    overall: true,
    checksPassed: [],
    checksFailed: [],
    neuronsFound: [],
  ),
  overall: false,
  backendSupport: BackendSupportResult(backend: 'nir', verdict: 'faithful'),
);

ProviderContainer _makeContainer(
  MockApiClient mockApi, {
  required String deployTarget,
}) {
  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(mockApi)],
  );
  container.listen(pipelineProvider, (_, _) {});
  container
      .read(workspaceProvider.notifier)
      .setSelectedDeployTarget(deployTarget);
  return container;
}

void _stubParseAndValidate(
  MockApiClient mockApi, {
  ValidationResult? validateResult,
}) {
  when(mockApi.parse(any)).thenAnswer((_) async => _parseResult);
  when(
    mockApi.validate(
      any,
      params: anyNamed('params'),
      backend: anyNamed('backend'),
    ),
  ).thenAnswer((_) async => validateResult ?? _passingValidateResult);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
  });

  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
  });

  group('Hardware target deploy readiness', () {
    test('exact support level -> DeployReadinessResult.ok', () async {
      final mockApi = MockApiClient();
      _stubParseAndValidate(mockApi);
      when(mockApi.previewDeployTarget(any, any)).thenAnswer(
        (_) async => const DeployPreviewResult(
          target: 'akida',
          code: '# generated',
          supportLevel: 'exact',
        ),
      );

      final container = _makeContainer(mockApi, deployTarget: 'akida');
      addTearDown(container.dispose);

      await container
          .read(pipelineProvider.notifier)
          .runParseAndValidate(_testSpec);
      await pumpEventQueue();

      final state = container.read(pipelineProvider);
      expect(state.deployReadinessStatus, StepStatus.success);
      expect(state.deployReadinessResult, const DeployReadinessResult.ok());
    });

    test(
      'unsupported support level -> DeployReadinessResult.unsupported',
      () async {
        final mockApi = MockApiClient();
        _stubParseAndValidate(mockApi);
        when(mockApi.previewDeployTarget(any, any)).thenAnswer(
          (_) async => const DeployPreviewResult(
            target: 'akida',
            code: '',
            supportLevel: 'unsupported',
            diagnostics: ['stdp_synapse not supported on akida'],
          ),
        );

        final container = _makeContainer(mockApi, deployTarget: 'akida');
        addTearDown(container.dispose);

        await container
            .read(pipelineProvider.notifier)
            .runParseAndValidate(_testSpec);
        await pumpEventQueue();

        final state = container.read(pipelineProvider);
        expect(state.deployReadinessStatus, StepStatus.success);
        expect(
          state.deployReadinessResult,
          const DeployReadinessResult.unsupported(
            level: 'unsupported',
            unsupportedNodes: [],
            diagnostics: ['stdp_synapse not supported on akida'],
          ),
        );
      },
    );

    test(
      'approximate support level -> DeployReadinessResult.unsupported',
      () async {
        final mockApi = MockApiClient();
        _stubParseAndValidate(mockApi);
        when(mockApi.previewDeployTarget(any, any)).thenAnswer(
          (_) async => const DeployPreviewResult(
            target: 'akida',
            code: '# generated',
            supportLevel: 'approximate',
            diagnostics: ['adaptive_lif approximated on akida'],
          ),
        );

        final container = _makeContainer(mockApi, deployTarget: 'akida');
        addTearDown(container.dispose);

        await container
            .read(pipelineProvider.notifier)
            .runParseAndValidate(_testSpec);
        await pumpEventQueue();

        final state = container.read(pipelineProvider);
        expect(
          state.deployReadinessResult,
          const DeployReadinessResult.unsupported(
            level: 'approximate',
            unsupportedNodes: [],
            diagnostics: ['adaptive_lif approximated on akida'],
          ),
        );
      },
    );

    test('io_error present -> DeployReadinessResult.error', () async {
      final mockApi = MockApiClient();
      _stubParseAndValidate(mockApi);
      when(mockApi.previewDeployTarget(any, any)).thenAnswer(
        (_) async => const DeployPreviewResult(
          target: 'akida',
          code: '',
          ioError: 'akida backend unavailable',
        ),
      );

      final container = _makeContainer(mockApi, deployTarget: 'akida');
      addTearDown(container.dispose);

      await container
          .read(pipelineProvider.notifier)
          .runParseAndValidate(_testSpec);
      await pumpEventQueue();

      final state = container.read(pipelineProvider);
      expect(state.deployReadinessStatus, StepStatus.error);
      expect(
        state.deployReadinessResult,
        const DeployReadinessResult.error(message: 'akida backend unavailable'),
      );
    });

    test('previewDeployTarget throws -> DeployReadinessResult.error', () async {
      final mockApi = MockApiClient();
      _stubParseAndValidate(mockApi);
      when(
        mockApi.previewDeployTarget(any, any),
      ).thenThrow(Exception('network timeout'));

      final container = _makeContainer(mockApi, deployTarget: 'akida');
      addTearDown(container.dispose);

      await container
          .read(pipelineProvider.notifier)
          .runParseAndValidate(_testSpec);
      await pumpEventQueue();

      final state = container.read(pipelineProvider);
      expect(state.deployReadinessStatus, StepStatus.error);
      expect(state.deployReadinessResult, isA<DeployReadinessError>());
    });
  });

  group('Simulator target deploy readiness mirrors preflight', () {
    test('preflight exact -> DeployReadinessResult.ok', () async {
      final mockApi = MockApiClient();
      _stubParseAndValidate(mockApi);
      when(mockApi.preflight(any, any)).thenAnswer(
        (_) async => const PreflightResult(
          level: 'exact',
          supportedNodes: [],
          approximateNodes: [],
          unsupportedNodes: [],
          diagnostics: [],
        ),
      );

      final container = _makeContainer(mockApi, deployTarget: 'lava_sim');
      addTearDown(container.dispose);

      await container
          .read(pipelineProvider.notifier)
          .runParseAndValidate(_testSpec);
      await pumpEventQueue();

      final state = container.read(pipelineProvider);
      expect(state.deployReadinessStatus, StepStatus.success);
      expect(state.deployReadinessResult, const DeployReadinessResult.ok());
      verifyNever(mockApi.previewDeployTarget(any, any));
    });

    test(
      'preflight unsupported -> DeployReadinessResult.unsupported',
      () async {
        final mockApi = MockApiClient();
        _stubParseAndValidate(mockApi);
        when(mockApi.preflight(any, any)).thenAnswer(
          (_) async => const PreflightResult(
            level: 'unsupported',
            supportedNodes: [],
            approximateNodes: [],
            unsupportedNodes: ['stdp_synapse'],
            diagnostics: ['STDP not supported on lava_sim'],
          ),
        );

        final container = _makeContainer(mockApi, deployTarget: 'lava_sim');
        addTearDown(container.dispose);

        await container
            .read(pipelineProvider.notifier)
            .runParseAndValidate(_testSpec);
        await pumpEventQueue();

        final state = container.read(pipelineProvider);
        expect(
          state.deployReadinessResult,
          const DeployReadinessResult.unsupported(
            level: 'unsupported',
            unsupportedNodes: ['stdp_synapse'],
            diagnostics: ['STDP not supported on lava_sim'],
          ),
        );
      },
    );

    test('preflight throws -> DeployReadinessResult.error', () async {
      final mockApi = MockApiClient();
      _stubParseAndValidate(mockApi);
      when(mockApi.preflight(any, any)).thenThrow(
        const ApiException(503, '{"detail": "simulator unreachable"}'),
      );

      final container = _makeContainer(mockApi, deployTarget: 'lava_sim');
      addTearDown(container.dispose);

      await container
          .read(pipelineProvider.notifier)
          .runParseAndValidate(_testSpec);
      await pumpEventQueue();

      final state = container.read(pipelineProvider);
      expect(state.deployReadinessStatus, StepStatus.error);
      expect(state.deployReadinessResult, isA<DeployReadinessError>());
    });
  });

  group('Stale-request guard', () {
    test(
      'two rapid runParseAndValidate calls: only the latest readiness result commits',
      () async {
        final mockApi = MockApiClient();
        when(mockApi.parse(any)).thenAnswer((_) async => _parseResult);
        when(
          mockApi.validate(
            any,
            params: anyNamed('params'),
            backend: anyNamed('backend'),
          ),
        ).thenAnswer((_) async => _passingValidateResult);

        // First run's preview never resolves before the second run starts.
        when(mockApi.previewDeployTarget('spec one', 'akida')).thenAnswer((
          _,
        ) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return const DeployPreviewResult(
            target: 'akida',
            code: '',
            supportLevel: 'unsupported',
            diagnostics: ['stale result — must not commit'],
          );
        });
        when(mockApi.previewDeployTarget('spec two', 'akida')).thenAnswer(
          (_) async => const DeployPreviewResult(
            target: 'akida',
            code: '# generated',
            supportLevel: 'exact',
          ),
        );

        final container = _makeContainer(mockApi, deployTarget: 'akida');
        addTearDown(container.dispose);

        final notifier = container.read(pipelineProvider.notifier);
        final firstRun = notifier.runParseAndValidate('spec one');
        await notifier.runParseAndValidate('spec two');
        await firstRun;
        // Let the slow ('spec one') readiness fetch resolve too, so the test
        // proves the stale one is discarded rather than merely "not yet in".
        await Future<void>.delayed(const Duration(milliseconds: 80));

        final state = container.read(pipelineProvider);
        expect(state.deployReadinessStatus, StepStatus.success);
        expect(state.deployReadinessResult, const DeployReadinessResult.ok());
      },
    );
  });

  group('Validate failure clears deploy readiness', () {
    test('validate overall:false clears deployReadinessResult', () async {
      final mockApi = MockApiClient();
      _stubParseAndValidate(mockApi, validateResult: _failingValidateResult);

      final container = _makeContainer(mockApi, deployTarget: 'akida');
      addTearDown(container.dispose);

      await container
          .read(pipelineProvider.notifier)
          .runParseAndValidate(_testSpec);
      await pumpEventQueue();

      final state = container.read(pipelineProvider);
      expect(state.deployReadinessStatus, StepStatus.idle);
      expect(state.deployReadinessResult, isNull);
      verifyNever(mockApi.previewDeployTarget(any, any));
    });

    test('validate throwing clears deployReadinessResult', () async {
      final mockApi = MockApiClient();
      when(mockApi.parse(any)).thenAnswer((_) async => _parseResult);
      when(
        mockApi.validate(
          any,
          params: anyNamed('params'),
          backend: anyNamed('backend'),
        ),
      ).thenThrow(Exception('validate service down'));

      final container = _makeContainer(mockApi, deployTarget: 'akida');
      addTearDown(container.dispose);

      await container
          .read(pipelineProvider.notifier)
          .runParseAndValidate(_testSpec);
      await pumpEventQueue();

      final state = container.read(pipelineProvider);
      expect(state.deployReadinessStatus, StepStatus.idle);
      expect(state.deployReadinessResult, isNull);
      verifyNever(mockApi.previewDeployTarget(any, any));
    });
  });
}
