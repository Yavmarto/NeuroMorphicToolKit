import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurosim_handoff.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurosim_import_contract.dart';

void main() {
  test('buildTarget creates the NeuroSim deep-link URL', () {
    const importContract = NeurosimImportContract(
      payloadType: 'neurocnl_import_contract',
      payloadVersion: '2026-04-29',
      sourceModule: 'neurocnl',
      semanticsMode: 'canonical_import',
      cnlSpec:
          'The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.5',
      graph: {
        'nodes': <Object>[],
        'edges': <Object>[],
        'metadata': {
          'zoom': 1.0,
          'pan': <double>[0.0, 0.0],
        },
      },
    );
    final target = NeurosimHandoff.buildTarget(
      importContract: importContract,
      origin: 'http://localhost:8000',
    );

    expect(target, isNotNull);
    expect(target!.url.scheme, 'http');
    expect(target.url.host, 'localhost');
    // Canvas is now served by the merged NeuroStudio backend at port 8000.
    expect(target.url.port, 8000);
    // Deep link targets /canvas inside the merged frontend.
    expect(target.url.path, '/canvas');
    expect(target.url.queryParameters.containsKey('import_contract'), isTrue);
    expect(
      NeurosimHandoff.buildDeepLink(importContract: importContract),
      '/canvas?import_contract=${target.url.queryParameters['import_contract']}',
    );
    expect(NeurosimHandoff.exceedsSafePayload(target), isFalse);
  });

  test('buildTarget respects the safe payload threshold', () {
    final largeSpec = List<String>.filled(7000, 'neuron').join(' ');
    final target = NeurosimHandoff.buildTarget(
      importContract: NeurosimImportContract(
        payloadType: 'neurocnl_import_contract',
        payloadVersion: '2026-04-29',
        sourceModule: 'neurocnl',
        semanticsMode: 'canonical_import',
        cnlSpec: largeSpec,
        graph: const {
          'nodes': <Object>[],
          'edges': <Object>[],
          'metadata': {
            'zoom': 1.0,
            'pan': <double>[0.0, 0.0],
          },
        },
      ),
      origin: 'http://localhost:8000',
    );

    expect(target, isNotNull);
    expect(NeurosimHandoff.exceedsSafePayload(target!), isTrue);
  });
}
