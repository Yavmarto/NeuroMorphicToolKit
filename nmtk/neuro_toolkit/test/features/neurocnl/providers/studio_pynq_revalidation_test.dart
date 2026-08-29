// Re-validating the network must not throw away a live deploy.
//
// The Deploy step re-runs `validate` every time it is opened, and it used to
// clear `deployAck` unconditionally. Walking to Review and back therefore wiped
// the deploy the board was still holding — the run controls disappeared, the
// results went with them, and the user had to redeploy to get back to where
// they already were.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/dataset_sample.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_pynq_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_pynq_deploy_service.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_target_registry_service.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

PynqNetworkResponse _response({required double weight}) {
  return PynqNetworkResponse(
    supportState: PynqSupportState.exportable,
    warnings: const <String>[],
    rejectionReasons: const <String>[],
    deployPayload: PynqDeployPayload(
      weights: <double>[weight],
      config: const PynqDeployConfig(
        threshold: 1.0,
        bitWidth: 8,
        scaleFactor: 1.0,
      ),
      layers: const <PynqLayerDescriptor>[
        PynqLayerDescriptor(inputSize: 4, outputSize: 2),
      ],
      bitstreamPath: 'snn_overlay.bit',
      registerMap: const PynqRegisterMap(<String, dynamic>{
        'dma_channel': 'axi_dma_0',
      }),
    ),
  );
}

const _ack = PynqDeployAck(
  status: 'success',
  message: 'Overlay loaded and configured successfully.',
  runtimeMode: PynqBackendRuntimeMode.hardware,
  preflightStatus: 'ok',
  overlayVersion: '2.0.0',
);

class _StubService extends StudioPynqDeployService {
  _StubService(this._response)
    : super(
        apiClient: ApiClient(baseUrl: 'http://localhost'),
        targetRegistryService: StudioTargetRegistryService(),
      );

  PynqNetworkResponse _response;
  set response(PynqNetworkResponse value) => _response = value;

  @override
  Future<PynqNetworkResponse> validate({
    required String spec,
    required int bitWidth,
    String? trainedNirBase64,
  }) async => _response;

  @override
  Future<PynqTrainedNir?> fetchLatestTrainedNir(String workspaceFolder) async =>
      null;

  @override
  Future<DatasetSample> fetchDatasetSample(
    String workspaceFolder, {
    int index = 0,
  }) async => throw const StudioPynqDeployException('no dataset here');
}

void main() {
  late _StubService service;
  late ProviderContainer container;

  setUp(() {
    service = _StubService(_response(weight: 1.0));
    container = ProviderContainer(
      overrides: [studioPynqDeployServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
  });

  test('an unchanged payload keeps the deploy the board is holding', () async {
    final notifier = container.read(studioPynqDeployProvider.notifier);
    await notifier.validate('spec');
    notifier.state = notifier.state.copyWith(deployAck: _ack);

    await notifier.validate('spec');

    expect(container.read(studioPynqDeployProvider).deployAck, isNotNull);
  });

  test('a changed payload discards it', () async {
    final notifier = container.read(studioPynqDeployProvider.notifier);
    await notifier.validate('spec');
    notifier.state = notifier.state.copyWith(deployAck: _ack);

    // Retraining moves a weight: what is on the board is no longer this network.
    service.response = _response(weight: 2.0);
    await notifier.validate('spec');

    expect(container.read(studioPynqDeployProvider).deployAck, isNull);
  });

  test('the preparation pass runs once per key, across remounts', () {
    final notifier = container.read(studioPynqDeployProvider.notifier);

    expect(notifier.claimPreparation('board-1::ws::1'), isTrue);
    expect(notifier.claimPreparation('board-1::ws::1'), isFalse);
    // A different network is a different question.
    expect(notifier.claimPreparation('board-1::ws::2'), isTrue);
  });

  test('a missing evaluation set is reported, not raised', () async {
    final notifier = container.read(studioPynqDeployProvider.notifier);

    await notifier.loadDatasetSample('ws');

    final state = container.read(studioPynqDeployProvider);
    expect(state.datasetSample, isNull);
    expect(state.datasetSampleIssue, 'no dataset here');
    expect(state.phase, isNot(StudioPynqDeployPhase.failed));
  });
}
