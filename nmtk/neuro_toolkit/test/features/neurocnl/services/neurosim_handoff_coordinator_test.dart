import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurosim_handoff.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurosim_handoff_coordinator.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurosim_import_contract.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({required this.importContract})
    : super(baseUrl: 'http://localhost:8000');

  final NeurosimImportContract importContract;
  String? receivedSpec;

  @override
  Future<NeurosimImportContract> prepareNeurosimHandoff(String spec) async {
    receivedSpec = spec;
    return importContract;
  }
}

NeurosimImportContract _decodeImportedContract(Uri uri) {
  final encoded = uri.queryParameters['import_contract']!;
  final padding = (4 - encoded.length % 4) % 4;
  final decoded = utf8.decode(base64Url.decode('$encoded${'=' * padding}'));
  return NeurosimImportContract.fromJson(
    jsonDecode(decoded) as Map<String, dynamic>,
  );
}

void main() {
  test('Coordinator uses normalized backend handoff CNL', () async {
    const rawSpec =
        'The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.15';
    const importContract = NeurosimImportContract(
      payloadType: 'neurocnl_import_contract',
      payloadVersion: '2026-04-29',
      sourceModule: 'neurocnl',
      semanticsMode: 'canonical_import',
      cnlSpec:
          "Create a population 'sensory' of 50 LIF neurons with tau_rc=0.02 and tau_ref=0.002.\n"
          "Create a population 'motor' of 50 LIF neurons with tau_rc=0.02 and tau_ref=0.002.\n"
          "Connect 'sensory' to 'motor' with a static synapse of weight 1 and delay 0.001.",
      graph: {
        'nodes': <Object>[],
        'edges': <Object>[],
        'metadata': {
          'zoom': 1.0,
          'pan': <double>[0.0, 0.0],
        },
      },
    );
    final apiClient = _FakeApiClient(importContract: importContract);
    final coordinator = NeurosimHandoffCoordinator(
      apiClient: apiClient,
      getOrigin: () => 'http://localhost:8000',
    );

    final preparation = await coordinator.prepareTarget(spec: rawSpec);

    expect(preparation.status, NeurosimHandoffPreparationStatus.ready);
    expect(apiClient.receivedSpec, rawSpec);
    expect(
      _decodeImportedContract(preparation.target!.url).cnlSpec,
      importContract.cnlSpec,
    );
  });

  test(
    'Coordinator keeps oversized handling tied to normalized payload',
    () async {
      final normalizedSpec = List<String>.filled(7000, 'neuron').join(' ');
      final coordinator = NeurosimHandoffCoordinator(
        apiClient: _FakeApiClient(
          importContract: NeurosimImportContract(
            payloadType: 'neurocnl_import_contract',
            payloadVersion: '2026-04-29',
            sourceModule: 'neurocnl',
            semanticsMode: 'canonical_import',
            cnlSpec: normalizedSpec,
            graph: const {
              'nodes': <Object>[],
              'edges': <Object>[],
              'metadata': {
                'zoom': 1.0,
                'pan': <double>[0.0, 0.0],
              },
            },
          ),
        ),
        getOrigin: () => 'http://localhost:8000',
      );

      final preparation = await coordinator.prepareTarget(spec: 'raw spec');

      expect(preparation.status, NeurosimHandoffPreparationStatus.ready);
      expect(NeurosimHandoff.exceedsSafePayload(preparation.target!), isTrue);
    },
  );
}
