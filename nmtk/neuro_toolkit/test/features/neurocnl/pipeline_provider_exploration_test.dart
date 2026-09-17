// ignore_for_file: avoid_redundant_argument_values

/// Exploration tests for Task 1.2 — validate backend hardcoding, updated
/// for Task 7.7 to assert the new target-aware behaviour from Task 3.2.
///
/// These tests now document the CORRECT post-Task-3.2 behaviour of
/// [PipelineController]:
/// * [runParseAndValidate] calls [ApiClient.validate] with `backend: 'lava_sim'`
///   when the workspace deploy target is `'lava_sim'` (Requirement 6.1).
/// * [runParseAndValidate] calls [ApiClient.validate] with
///   `backend: 'snntorch_sim'` when the workspace deploy target is
///   `'snntorch_sim'` (Requirement 6.1).
///
/// The hardware-target preservation tests assert that selecting a hardware /
/// RTL target (`'sc_neurocore_fpga'`, `'pynq'`, `'akida'`, `'lava'`) or no
/// target still produces `backend: 'nir'` (Requirement 6.2).
///
/// Requirements: 6.1, 6.2
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/simulator_preflight.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

import 'providers_test.mocks.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

const _testSpec = 'MUST fire ONLY IF membrane potential exceeds 1.5';

const _parseResult = ParseResult(sentences: [], total: 0, errors: 0);
const _validateResult = ValidationResult(
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
const _preflightResult = PreflightResult(
  level: 'exact',
  supportedNodes: [],
  approximateNodes: [],
  unsupportedNodes: [],
  diagnostics: [],
);

/// Creates a [ProviderContainer] with a mocked [ApiClient] and the workspace
/// deploy target pre-set to [deployTarget].
ProviderContainer _makeContainer(
  MockApiClient mockApi, {
  required String deployTarget,
}) {
  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(mockApi)],
  );
  // Set the selected deploy target on the workspace so the pipeline provider
  // can read it when target-aware logic is wired in Task 3.2.
  container
      .read(workspaceProvider.notifier)
      .setSelectedDeployTarget(deployTarget);
  return container;
}

/// Sets up standard mock stubs that make parse and validate succeed.
void _stubSuccess(MockApiClient mockApi) {
  when(mockApi.parse(any)).thenAnswer((_) async => _parseResult);
  when(
    mockApi.validate(
      any,
      params: anyNamed('params'),
      backend: anyNamed('backend'),
    ),
  ).thenAnswer((_) async => _validateResult);
  // Stub preflight so that the simulatorPreflightProvider call (triggered
  // after a successful validate for simulator targets) does not throw
  // a MissingStubError (Requirement 10.1 wired in Task 3.2).
  when(mockApi.preflight(any, any)).thenAnswer((_) async => _preflightResult);
}

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

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

  // ── Updated exploration tests (now assert Task 3.2 correct behaviour) ───────
  //
  // These tests were originally written to assert `backend: 'nir'` for
  // simulator targets (documenting the old hardcoded behaviour). Task 3.2
  // made runParseAndValidate target-aware, so these tests are updated to
  // assert the NEW correct behaviour:
  //   - lava_sim  → api.validate(..., backend: 'lava_sim')
  //   - snntorch_sim → api.validate(..., backend: 'snntorch_sim')
  // Both confirm Requirements 6.1 is implemented correctly.

  group('Exploration — validate uses simulator backend (post-Task 3.2)', () {
    test(
      'lava_sim target: runParseAndValidate calls api.validate with backend lava_sim',
      () async {
        // UPDATED EXPLORATION TEST — verifies Task 3.2 is correctly wired.
        // Requirements 6.1: simulator targets are passed as the backend parameter.
        final mockApi = MockApiClient();
        _stubSuccess(mockApi);

        final container = _makeContainer(mockApi, deployTarget: 'lava_sim');
        addTearDown(container.dispose);

        await container
            .read(pipelineProvider.notifier)
            .runParseAndValidate(_testSpec);

        final captured = verify(
          mockApi.validate(
            _testSpec,
            params: anyNamed('params'),
            backend: captureAnyNamed('backend'),
          ),
        ).captured;

        // Task 3.2 correct behaviour: simulator target id is passed as backend.
        expect(
          captured.single,
          'lava_sim',
          reason:
              'Requirement 6.1: lava_sim target must pass backend: lava_sim '
              'to api.validate (Task 3.2 confirmed)',
        );
      },
    );

    test(
      'snntorch_sim target: runParseAndValidate calls api.validate with backend snntorch_sim',
      () async {
        // UPDATED EXPLORATION TEST — verifies Task 3.2 is correctly wired.
        // Requirements 6.1: simulator targets are passed as the backend parameter.
        final mockApi = MockApiClient();
        _stubSuccess(mockApi);

        final container = _makeContainer(mockApi, deployTarget: 'snntorch_sim');
        addTearDown(container.dispose);

        await container
            .read(pipelineProvider.notifier)
            .runParseAndValidate(_testSpec);

        final captured = verify(
          mockApi.validate(
            _testSpec,
            params: anyNamed('params'),
            backend: captureAnyNamed('backend'),
          ),
        ).captured;

        // Task 3.2 correct behaviour: simulator target id is passed as backend.
        expect(
          captured.single,
          'snntorch_sim',
          reason:
              'Requirement 6.1: snntorch_sim target must pass backend: snntorch_sim '
              'to api.validate (Task 3.2 confirmed)',
        );
      },
    );
  });

  // ── Preservation test (must pass now AND after Task 3.2) ─────────────────
  //
  // Requirement 6.2: when a hardware target is selected, the pipeline provider
  // MUST pass `backend: 'nir'` to api.validate — both before and after
  // Task 3.2 changes validate behaviour for simulator targets.

  group('Preservation — hardware target always uses nir backend', () {
    test(
      'sc_neurocore_fpga target: runParseAndValidate calls api.validate with backend nir',
      () async {
        // PRESERVATION TEST — must pass now AND after Task 3.2.
        // Validates Requirement 6.2: hardware targets always use backend: 'nir'.
        final mockApi = MockApiClient();
        _stubSuccess(mockApi);

        final container = _makeContainer(
          mockApi,
          deployTarget: 'sc_neurocore_fpga',
        );
        addTearDown(container.dispose);

        await container
            .read(pipelineProvider.notifier)
            .runParseAndValidate(_testSpec);

        final captured = verify(
          mockApi.validate(
            _testSpec,
            params: anyNamed('params'),
            backend: captureAnyNamed('backend'),
          ),
        ).captured;

        expect(
          captured.single,
          'nir',
          reason:
              'Hardware/RTL target (sc_neurocore_fpga) must always use '
              'backend: nir '
              '(Requirement 6.2 — no regression after Task 3.2)',
        );
      },
    );

    test(
      'pynq target: runParseAndValidate calls api.validate with backend nir',
      () async {
        // PRESERVATION TEST — must pass now AND after Task 3.2.
        final mockApi = MockApiClient();
        _stubSuccess(mockApi);

        final container = _makeContainer(mockApi, deployTarget: 'pynq');
        addTearDown(container.dispose);

        await container
            .read(pipelineProvider.notifier)
            .runParseAndValidate(_testSpec);

        final captured = verify(
          mockApi.validate(
            _testSpec,
            params: anyNamed('params'),
            backend: captureAnyNamed('backend'),
          ),
        ).captured;

        expect(
          captured.single,
          'nir',
          reason: 'Hardware target (pynq) must always use backend: nir',
        );
      },
    );

    test(
      'akida target: runParseAndValidate calls api.validate with backend nir',
      () async {
        // PRESERVATION TEST — must pass now AND after Task 3.2.
        final mockApi = MockApiClient();
        _stubSuccess(mockApi);

        final container = _makeContainer(mockApi, deployTarget: 'akida');
        addTearDown(container.dispose);

        await container
            .read(pipelineProvider.notifier)
            .runParseAndValidate(_testSpec);

        final captured = verify(
          mockApi.validate(
            _testSpec,
            params: anyNamed('params'),
            backend: captureAnyNamed('backend'),
          ),
        ).captured;

        expect(
          captured.single,
          'nir',
          reason: 'Hardware target (akida) must always use backend: nir',
        );
      },
    );

    test(
      'lava (hardware) target: runParseAndValidate calls api.validate with backend nir',
      () async {
        // PRESERVATION TEST — must pass now AND after Task 3.2.
        // Note: 'lava' here is the Loihi2 hardware target, not a simulator.
        final mockApi = MockApiClient();
        _stubSuccess(mockApi);

        final container = _makeContainer(mockApi, deployTarget: 'lava');
        addTearDown(container.dispose);

        await container
            .read(pipelineProvider.notifier)
            .runParseAndValidate(_testSpec);

        final captured = verify(
          mockApi.validate(
            _testSpec,
            params: anyNamed('params'),
            backend: captureAnyNamed('backend'),
          ),
        ).captured;

        expect(
          captured.single,
          'nir',
          reason: 'Hardware target (lava/Loihi2) must always use backend: nir',
        );
      },
    );

    test(
      'no target set: runParseAndValidate calls api.validate with backend nir',
      () async {
        // PRESERVATION TEST — no deploy target selected at all.
        // The default WorkspaceState.selectedDeployTarget is 'pynq' (a hardware
        // target), so this also exercises the "not set / hardware" path.
        final mockApi = MockApiClient();
        _stubSuccess(mockApi);

        // Use default workspace (no explicit setSelectedDeployTarget call).
        final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWithValue(mockApi)],
        );
        addTearDown(container.dispose);

        await container
            .read(pipelineProvider.notifier)
            .runParseAndValidate(_testSpec);

        final captured = verify(
          mockApi.validate(
            _testSpec,
            params: anyNamed('params'),
            backend: captureAnyNamed('backend'),
          ),
        ).captured;

        expect(
          captured.single,
          'nir',
          reason: 'Default workspace target is hardware; must use backend: nir',
        );
      },
    );
  });
}
