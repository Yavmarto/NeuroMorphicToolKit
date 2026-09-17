import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/services/akida_handoff.dart';
import 'package:neuro_toolkit/features/neurocnl/services/akida_handoff_coordinator.dart';

void main() {
  final mappedNetwork = <String, dynamic>{
    'akida_version': 'akida2',
    'populations': [
      {'id': 'sensor', 'size': 8},
      {'id': 'motor', 'size': 4},
    ],
    'connections': [
      {'source': 'sensor', 'target': 'motor', 'units': 4},
    ],
    'network_summary': {'n_populations': 2, 'n_connections': 1},
  };

  test('Coordinator returns ready status when mapped network exists', () {
    final coordinator = AkidaHandoffCoordinator(
      getOrigin: () => 'http://localhost:8000',
    );

    final preparation = coordinator.prepareTarget(
      mappedNetwork: mappedNetwork,
      bitWidth: 2,
      akidaVersion: 'akida2',
      supportState: 'exportable_scaffold_with_warnings',
      topologyVerdict: 'approximate',
      warnings: const ['Using approximate Akida2 block hints.'],
    );

    expect(preparation.status, AkidaHandoffPreparationStatus.ready);
    expect(preparation.target, isNotNull);
    expect(preparation.target!.url.port, 8002);
    expect(
      preparation.target!.url.queryParameters.containsKey('import_akida'),
      isTrue,
    );

    final encoded = preparation.target!.url.queryParameters['import_akida']!;
    final padding = (4 - encoded.length % 4) % 4;
    final decoded = utf8.decode(base64Url.decode('$encoded${'=' * padding}'));
    final json = jsonDecode(decoded) as Map<String, dynamic>;

    expect(json['mapped_network'], isA<Map<String, dynamic>>());
    expect(
      (json['runtime_context'] as Map<String, dynamic>)['weight_bit_width'],
      2,
    );
    expect(
      (json['runtime_context'] as Map<String, dynamic>)['akida_version'],
      'akida2',
    );
    expect(
      AkidaHandoff.buildDeepLink(
        mappedNetwork: mappedNetwork,
        bitWidth: 2,
        akidaVersion: 'akida2',
        supportState: 'exportable_scaffold_with_warnings',
        topologyVerdict: 'approximate',
        warnings: const ['Using approximate Akida2 block hints.'],
      ),
      '/?import_akida=$encoded',
    );
  });

  test('Coordinator reports missing mapping when mapped network is absent', () {
    final coordinator = AkidaHandoffCoordinator(
      getOrigin: () => 'http://localhost:8000',
    );

    final preparation = coordinator.prepareTarget(
      mappedNetwork: null,
      bitWidth: 4,
      akidaVersion: 'akida1',
    );

    expect(
      preparation.status,
      AkidaHandoffPreparationStatus.mappingUnavailable,
    );
    expect(preparation.errorMessage, isNotNull);
  });

  test('Akida handoff flags oversized payloads without changing routes', () {
    final largeMappedNetwork = <String, dynamic>{
      'akida_version': 'akida1',
      'populations': List<Map<String, dynamic>>.generate(
        600,
        (index) => {'id': 'pop_$index', 'size': 4},
      ),
      'connections': List<Map<String, dynamic>>.generate(
        500,
        (index) => {
          'source': 'pop_$index',
          'target': 'pop_${index + 1}',
          'units': 4,
        },
      ),
    };

    final target = AkidaHandoff.buildTarget(
      mappedNetwork: largeMappedNetwork,
      bitWidth: 4,
      akidaVersion: 'akida1',
      origin: 'http://localhost:8000',
    );

    expect(target, isNotNull);
    expect(AkidaHandoff.exceedsSafePayload(target!), isTrue);
    expect(target.url.port, 8002);
  });
}
