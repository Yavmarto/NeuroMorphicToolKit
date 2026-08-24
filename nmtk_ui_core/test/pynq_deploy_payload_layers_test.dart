import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// The layer chain is the only place the network's shape exists on either side
/// of the board boundary — overlay-v2's engine has no neuron-count registers. If
/// it does not survive the trip from the backend's deploy payload through this
/// model and back out to launcher control, the board cannot be told how wide an
/// input frame is, and every run fails with `Expected N input words`.
void main() {
  Map<String, dynamic> payloadJson({List<Map<String, dynamic>>? layers}) {
    return <String, dynamic>{
      'weights': <double>[1.0, 2.0],
      'config': <String, dynamic>{},
      'bitstream_path': 'snn_overlay.bit',
      'overlay_id': 'snn_overlay_v2',
      'overlay_version': '2.0.0',
      'register_map': <String, dynamic>{'base_address': 0x40000000},
      'layers': ?layers,
    };
  }

  const denseLayer = <String, dynamic>{
    'input_size': 32,
    'output_size': 4,
    'weight_offset': 0,
    'threshold': 27,
    'leak_shift': 4,
    'refractory': 2,
    'source': 'lif_a',
    'target': 'lif_b',
  };

  group('PynqDeployPayload layers', () {
    test('parses every descriptor field', () {
      final payload = PynqDeployPayload.fromJson(
        payloadJson(layers: [denseLayer]),
      );

      expect(payload.layers, hasLength(1));
      final layer = payload.layers.single;
      expect(layer.inputSize, 32);
      expect(layer.outputSize, 4);
      expect(layer.weightOffset, 0);
      expect(layer.threshold, 27);
      expect(layer.leakShift, 4);
      expect(layer.refractory, 2);
      expect(layer.source, 'lif_a');
      expect(layer.target, 'lif_b');
    });

    test('keeps chain order across a round trip', () {
      final payload = PynqDeployPayload.fromJson(
        payloadJson(
          layers: [
            {'input_size': 784, 'output_size': 256, 'weight_offset': 0},
            {'input_size': 256, 'output_size': 10, 'weight_offset': 200704},
          ],
        ),
      );

      final restored = PynqDeployPayload.fromJson(payload.toJson());

      expect(
        restored.layers.map((layer) => layer.inputSize),
        <int>[784, 256],
        reason:
            'the engine walks layers in order; a reorder is a wrong network',
      );
      expect(restored.layers.last.weightOffset, 200704);
    });

    test('does not leave layers in additionalFields', () {
      final payload = PynqDeployPayload.fromJson(
        payloadJson(layers: [denseLayer]),
      );

      expect(payload.additionalFields.containsKey('layers'), isFalse);
    });

    test('omits the key entirely when there are no layers', () {
      // An empty list has to fail on the board as "no layers", not be read as a
      // deliberate zero-layer network.
      final payload = PynqDeployPayload.fromJson(payloadJson());

      expect(payload.layers, isEmpty);
      expect(payload.toJson().containsKey('layers'), isFalse);
    });
  });

  group('PynqBoardState', () {
    test(
      'a stored board that nothing has contacted does not say "Unpaired"',
      () {
        // The record only exists because the user paired the board. "No board at
        // all" is a separate branch in both the Setup dot and the setup pane.
        expect(PynqBoardState.unpaired.label, 'Not checked yet');
        expect(PynqBoardState.unpaired.apiValue, 'unpaired');
      },
    );
  });
}
