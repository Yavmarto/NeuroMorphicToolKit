import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurochip_handoff.dart';

void main() {
  test(
    'buildTarget creates the Neurochip deep-link URL with correct port and param',
    () {
      final networkJson = <String, dynamic>{
        'num_neurons': 20,
        'num_synapses': 100,
        'neuron_model': 'LIF',
        'populations': <Map<String, dynamic>>[
          {'name': 'sensory', 'size': 10},
          {'name': 'motor', 'size': 10},
        ],
        'connections': <Map<String, dynamic>>[
          {'pre': 'sensory', 'post': 'motor', 'weight_count': 100},
        ],
        'weight_bit_width': 8,
        'network_depth': 2,
      };

      final target = NeurochipHandoff.buildTarget(
        networkJson: networkJson,
        origin: 'http://localhost:8000',
        targetId: 'teensy41',
        targetLabel: 'Teensy 4.1',
        destinationWorkspace: 'teensy',
        readinessSummary: const <String, dynamic>{
          'validation_ready': true,
          'generated_ready': true,
        },
      );

      expect(target, isNotNull);
      expect(target!.url.scheme, 'http');
      expect(target.url.host, 'localhost');
      expect(target.url.port, 8002);
      expect(target.url.path, '/teensy');
      expect(
        target.url.queryParameters.containsKey('import_network_handoff'),
        isTrue,
      );
      expect(
        NeurochipHandoff.buildDeepLink(
          networkJson: networkJson,
          targetId: 'teensy41',
          targetLabel: 'Teensy 4.1',
          destinationWorkspace: 'teensy',
          readinessSummary: const <String, dynamic>{
            'validation_ready': true,
            'generated_ready': true,
          },
        ),
        '/teensy?import_network_handoff=${target.url.queryParameters['import_network_handoff']}',
      );
      expect(NeurochipHandoff.exceedsSafePayload(target), isFalse);
    },
  );

  test('buildTarget encodes network JSON that round-trips correctly', () {
    final networkJson = <String, dynamic>{
      'num_neurons': 20,
      'num_synapses': 100,
      'neuron_model': 'LIF',
      'populations': <dynamic>[],
      'connections': <dynamic>[],
      'weight_bit_width': 8,
      'network_depth': 1,
    };

    final target = NeurochipHandoff.buildTarget(
      networkJson: networkJson,
      origin: 'http://localhost:8000',
      targetId: 'teensy41',
      targetLabel: 'Teensy 4.1',
      destinationWorkspace: 'teensy',
    );

    expect(target, isNotNull);
    final encoded = target!.url.queryParameters['import_network_handoff']!;
    final padding = (4 - encoded.length % 4) % 4;
    final decoded = utf8.decode(base64Url.decode('$encoded${'=' * padding}'));
    final roundTripped = jsonDecode(decoded) as Map<String, dynamic>;
    expect(roundTripped['target_id'], 'teensy41');
    expect(roundTripped['destination_workspace'], 'teensy');
    final network = roundTripped['network'] as Map<String, dynamic>;
    expect(network['num_neurons'], 20);
    expect(network['neuron_model'], 'LIF');
    expect(network['weight_bit_width'], 8);
  });

  test('buildTarget returns null when networkJson is empty', () {
    final target = NeurochipHandoff.buildTarget(
      networkJson: <String, dynamic>{},
      origin: 'http://localhost:8000',
      targetId: 'teensy41',
      targetLabel: 'Teensy 4.1',
      destinationWorkspace: 'teensy',
    );
    expect(target, isNull);
  });

  test('buildTarget returns null when origin is empty', () {
    final target = NeurochipHandoff.buildTarget(
      networkJson: <String, dynamic>{'num_neurons': 1},
      origin: '',
      targetId: 'teensy41',
      targetLabel: 'Teensy 4.1',
      destinationWorkspace: 'teensy',
    );
    expect(target, isNull);
  });

  test('buildTarget preserves PYNQ workspace handoff details', () {
    final target = NeurochipHandoff.buildTarget(
      networkJson: <String, dynamic>{'num_neurons': 8, 'num_synapses': 16},
      origin: 'http://localhost:8000',
      targetId: 'pynq',
      targetLabel: 'PYNQ Z2',
      destinationWorkspace: 'pynq',
    );

    expect(target, isNotNull);
    expect(target!.url.path, '/pynq');
    final encoded = target.url.queryParameters['import_network_handoff']!;
    final padding = (4 - encoded.length % 4) % 4;
    final decoded = utf8.decode(base64Url.decode('$encoded${'=' * padding}'));
    final roundTripped = jsonDecode(decoded) as Map<String, dynamic>;
    expect(roundTripped['target_id'], 'pynq');
    expect(roundTripped['destination_workspace'], 'pynq');
  });

  test('buildTarget preserves Akida workspace handoff details', () {
    final target = NeurochipHandoff.buildTarget(
      networkJson: <String, dynamic>{'num_neurons': 8, 'num_synapses': 16},
      origin: 'http://localhost:8000',
      targetId: 'akida',
      targetLabel: 'BrainChip Akida',
      destinationWorkspace: 'akida',
    );

    expect(target, isNotNull);
    expect(target!.url.path, '/akida');
    final encoded = target.url.queryParameters['import_network_handoff']!;
    final padding = (4 - encoded.length % 4) % 4;
    final decoded = utf8.decode(base64Url.decode('$encoded${'=' * padding}'));
    final roundTripped = jsonDecode(decoded) as Map<String, dynamic>;
    expect(roundTripped['target_id'], 'akida');
    expect(roundTripped['destination_workspace'], 'akida');
  });

  test('exceedsSafePayload returns true for large network', () {
    final largeNetworkJson = <String, dynamic>{
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

    final target = NeurochipHandoff.buildTarget(
      networkJson: largeNetworkJson,
      origin: 'http://localhost:8000',
      targetId: 'teensy41',
      targetLabel: 'Teensy 4.1',
      destinationWorkspace: 'teensy',
    );

    expect(target, isNotNull);
    expect(NeurochipHandoff.exceedsSafePayload(target!), isTrue);
  });
}
