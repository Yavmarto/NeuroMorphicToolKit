import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurochip_handoff.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurochip_handoff_coordinator.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.networkPayload, this.shouldThrow = false})
    : super(baseUrl: 'http://localhost:8000');

  final Map<String, dynamic>? networkPayload;
  final bool shouldThrow;
  String? receivedSpec;

  @override
  Future<Map<String, dynamic>> deployToNeurochip(
    String spec, {
    int bitWidth = 8,
  }) async {
    receivedSpec = spec;
    if (shouldThrow) {
      throw const ApiException(422, '{"detail": {"error": "not_deployable"}}');
    }
    return networkPayload!;
  }
}

void main() {
  const defaultPayload = <String, dynamic>{
    'num_neurons': 20,
    'num_synapses': 100,
    'neuron_model': 'LIF',
    'populations': <dynamic>[],
    'connections': <dynamic>[],
    'weight_bit_width': 8,
    'network_depth': 2,
  };

  test('Coordinator returns ready status when deploy succeeds', () async {
    const spec =
        'The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0';
    final apiClient = _FakeApiClient(networkPayload: defaultPayload);
    final coordinator = NeurochipHandoffCoordinator(
      apiClient: apiClient,
      getOrigin: () => 'http://localhost:8000',
    );

    final preparation = await coordinator.prepareTarget(
      spec: spec,
      targetId: 'teensy41',
      targetLabel: 'Teensy 4.1',
      destinationWorkspace: 'teensy',
      readinessSummary: const <String, dynamic>{'validation_ready': true},
    );

    expect(preparation.status, NeurochipHandoffPreparationStatus.ready);
    expect(apiClient.receivedSpec, spec);
    expect(preparation.target, isNotNull);
    expect(preparation.target!.url.port, 8002);
    expect(
      preparation.target!.url.queryParameters.containsKey(
        'import_network_handoff',
      ),
      isTrue,
    );
  });

  test('Coordinator prepares a PYNQ Studio handoff target', () async {
    final apiClient = _FakeApiClient(networkPayload: defaultPayload);
    final coordinator = NeurochipHandoffCoordinator(
      apiClient: apiClient,
      getOrigin: () => 'http://localhost:8000',
    );

    final preparation = await coordinator.prepareTarget(
      spec: 'valid spec',
      targetId: 'pynq',
      targetLabel: 'PYNQ Z2',
      destinationWorkspace: 'pynq',
    );

    expect(preparation.status, NeurochipHandoffPreparationStatus.ready);
    expect(preparation.target, isNotNull);
    expect(preparation.target!.url.path, '/pynq');
  });

  test('Coordinator prepares an Akida Studio handoff target', () async {
    final apiClient = _FakeApiClient(networkPayload: defaultPayload);
    final coordinator = NeurochipHandoffCoordinator(
      apiClient: apiClient,
      getOrigin: () => 'http://localhost:8000',
    );

    final preparation = await coordinator.prepareTarget(
      spec: 'valid spec',
      targetId: 'akida',
      targetLabel: 'BrainChip Akida',
      destinationWorkspace: 'akida',
    );

    expect(preparation.status, NeurochipHandoffPreparationStatus.ready);
    expect(preparation.target, isNotNull);
    expect(preparation.target!.url.path, '/akida');
  });

  test(
    'Coordinator returns deploymentFailed when backend rejects spec',
    () async {
      final apiClient = _FakeApiClient(shouldThrow: true);
      final coordinator = NeurochipHandoffCoordinator(
        apiClient: apiClient,
        getOrigin: () => 'http://localhost:8000',
      );

      final preparation = await coordinator.prepareTarget(
        spec: 'invalid spec',
        targetId: 'teensy41',
        targetLabel: 'Teensy 4.1',
        destinationWorkspace: 'teensy',
      );

      expect(
        preparation.status,
        NeurochipHandoffPreparationStatus.deploymentFailed,
      );
      expect(preparation.errorMessage, isNotNull);
      expect(preparation.target, isNull);
    },
  );

  test('Coordinator returns emptySpec when spec is blank', () async {
    final apiClient = _FakeApiClient(networkPayload: defaultPayload);
    final coordinator = NeurochipHandoffCoordinator(
      apiClient: apiClient,
      getOrigin: () => 'http://localhost:8000',
    );

    final preparation = await coordinator.prepareTarget(
      spec: '   ',
      targetId: 'teensy41',
      targetLabel: 'Teensy 4.1',
      destinationWorkspace: 'teensy',
    );

    expect(preparation.status, NeurochipHandoffPreparationStatus.emptySpec);
    expect(apiClient.receivedSpec, isNull);
  });

  test('Coordinator returns unavailable when origin is null', () async {
    final apiClient = _FakeApiClient(networkPayload: defaultPayload);
    final coordinator = NeurochipHandoffCoordinator(
      apiClient: apiClient,
      getOrigin: () => null,
    );

    final preparation = await coordinator.prepareTarget(
      spec: 'some spec',
      targetId: 'teensy41',
      targetLabel: 'Teensy 4.1',
      destinationWorkspace: 'teensy',
    );

    expect(preparation.status, NeurochipHandoffPreparationStatus.unavailable);
    expect(apiClient.receivedSpec, isNull);
  });

  test('Coordinator handles oversized payload detection', () async {
    final largePayload = <String, dynamic>{
      'num_neurons': 10000,
      'populations': List<Map<String, dynamic>>.generate(
        500,
        (i) => {'name': 'pop_$i', 'size': 20},
      ),
      'connections': List<Map<String, dynamic>>.generate(
        200,
        (i) => {'pre': 'pop_$i', 'post': 'pop_${i + 1}', 'weight_count': 400},
      ),
    };
    final coordinator = NeurochipHandoffCoordinator(
      apiClient: _FakeApiClient(networkPayload: largePayload),
      getOrigin: () => 'http://localhost:8000',
    );

    final preparation = await coordinator.prepareTarget(
      spec: 'big spec',
      targetId: 'teensy41',
      targetLabel: 'Teensy 4.1',
      destinationWorkspace: 'teensy',
    );

    expect(preparation.status, NeurochipHandoffPreparationStatus.ready);
    expect(NeurochipHandoff.exceedsSafePayload(preparation.target!), isTrue);
  });
}
