import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/dataset_sample.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_pynq_deploy_provider.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Overlay-v2 consumes one word per input neuron per timestep. The execution
/// pane still asks for neuron *indices* because typing three numbers beats
/// typing 784 zeros, so the expansion has to happen here — and it has to happen
/// at all: v1's protocol sent the index list verbatim, which the v2 worker and
/// simulator both reject with `Expected N input words`.
void main() {
  StudioPynqDeployState stateWith({
    required int inputSize,
    required int outputSize,
    required String indices,
    int timesteps = 1,
  }) {
    return StudioPynqDeployState(
      inputSpikesText: indices,
      timesteps: timesteps,
      exportResult: PynqNetworkResponse(
        supportState: PynqSupportState.exportable,
        warnings: const <String>[],
        rejectionReasons: const <String>[],
        deployPayload: PynqDeployPayload(
          weights: const <double>[],
          config: const PynqDeployConfig(
            threshold: 1.0,
            bitWidth: 8,
            scaleFactor: 1.0,
          ),
          layers: <PynqLayerDescriptor>[
            PynqLayerDescriptor(inputSize: inputSize, outputSize: outputSize),
          ],
          bitstreamPath: 'snn_overlay.bit',
          registerMap: const PynqRegisterMap(<String, dynamic>{
            'dma_channel': 'axi_dma_0',
            'timestep_us': 1000,
          }),
        ),
      ),
    );
  }

  test('reads the input width from the first layer descriptor', () {
    final state = stateWith(inputSize: 32, outputSize: 4, indices: '0');

    expect(state.inputNeuronCount, 32);
  });

  test('expands indices to one word per neuron per timestep', () {
    final frames = stateWith(
      inputSize: 4,
      outputSize: 2,
      indices: '0, 3',
      timesteps: 3,
    ).buildInputFrames();

    expect(frames, hasLength(12), reason: '4 neurons x 3 timesteps');
    // Each named neuron spikes on every timestep — the static-input scheme the
    // trained network was evaluated under.
    expect(frames, <int>[1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1]);
  });

  test('neuron 0 is representable', () {
    // v1 encoded a firing neuron as its own index, so a spiking neuron 0 was
    // byte-identical to silence.
    final frames = stateWith(
      inputSize: 3,
      outputSize: 1,
      indices: '0',
    ).buildInputFrames();

    expect(frames, <int>[1, 0, 0]);
  });

  test('an all-silent frame is still a full-width transfer', () {
    final frames = stateWith(
      inputSize: 5,
      outputSize: 1,
      indices: '',
      timesteps: 2,
    ).buildInputFrames();

    expect(frames, hasLength(10));
    expect(frames.every((word) => word == 0), isTrue);
  });

  test('an out-of-range index is named, not dropped', () {
    final state = stateWith(inputSize: 4, outputSize: 2, indices: '1, 9');

    expect(
      () => state.buildInputFrames(),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          allOf(contains('9'), contains('4 input neurons'), contains('0 to 3')),
        ),
      ),
    );
  });

  test('a payload with no layers says so instead of guessing a width', () {
    const state = StudioPynqDeployState(inputSpikesText: '0');

    expect(
      () => state.buildInputFrames(),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('no layer descriptors'),
        ),
      ),
    );
  });

  group('evaluation samples', () {
    DatasetSample sampleOf(List<int> spikes, {int? label}) => DatasetSample(
      filename: 'eval_testloader_mnist_val.pt',
      sampleIndex: 0,
      sampleCount: 1000,
      inputWidth: spikes.length,
      inputSpikes: spikes,
      spikeCount: spikes.where((value) => value > 0).length,
      label: label,
    );

    test('presents the sample unchanged on every timestep', () {
      // Rate coding over a static frame — how the model was trained and scored.
      final state = stateWith(
        inputSize: 4,
        outputSize: 2,
        indices: '0',
        timesteps: 3,
      ).copyWith(datasetSample: sampleOf(<int>[0, 1, 1, 0], label: 7));

      expect(state.buildInputFrames(), <int>[
        0, 1, 1, 0, //
        0, 1, 1, 0, //
        0, 1, 1, 0, //
      ]);
    });

    test('a sample of the wrong width is named, not silently truncated', () {
      final state = stateWith(
        inputSize: 4,
        outputSize: 2,
        indices: '0',
      ).copyWith(datasetSample: sampleOf(<int>[1, 0, 1]));

      expect(
        () => state.buildInputFrames(),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            allOf(contains('3 values'), contains('4 inputs')),
          ),
        ),
      );
    });

    test('typing neurons ignores a loaded sample', () {
      final state = stateWith(inputSize: 4, outputSize: 2, indices: '3')
          .copyWith(
            datasetSample: sampleOf(<int>[1, 1, 1, 1]),
            inputSource: StudioPynqInputSource.manualIndices,
          );

      expect(state.buildInputFrames(), <int>[0, 0, 0, 1]);
    });

    test('a run needs a stimulus that matches the chosen source', () {
      final withoutSample = stateWith(
        inputSize: 4,
        outputSize: 2,
        indices: '0',
      );
      expect(withoutSample.hasStimulus, isFalse);
      expect(
        withoutSample
            .copyWith(datasetSample: sampleOf(<int>[1, 0, 0, 0]))
            .hasStimulus,
        isTrue,
      );
      expect(
        withoutSample
            .copyWith(inputSource: StudioPynqInputSource.manualIndices)
            .hasStimulus,
        isTrue,
      );
    });
  });
}
