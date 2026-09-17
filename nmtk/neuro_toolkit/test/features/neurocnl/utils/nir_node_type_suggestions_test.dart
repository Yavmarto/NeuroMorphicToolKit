import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/nir_node_type_suggestions.dart';

NirNodeType _makeType(String id, String displayName) => NirNodeType(
  id: id,
  displayName: displayName,
  category: 'test',
  icon: Icons.circle,
  ports: const <NirPortDef>[],
  parameters: const <NirParameterDef>[],
);

void main() {
  final registry = <String, NirNodeType>{
    'nir.lif': _makeType('nir.lif', 'LIF Neuron'),
    'nir.lifr': _makeType('nir.lifr', 'LIF Neuron (Refractory)'),
    'nir.synapse': _makeType('nir.synapse', 'Synapse'),
    'nir.input': _makeType('nir.input', 'Input Encoder'),
    'nir.output': _makeType('nir.output', 'Output Decoder'),
    'nir.population': _makeType('nir.population', 'Population'),
  };

  group('suggestNirNodeTypes', () {
    test('returns empty list for blank input', () {
      expect(suggestNirNodeTypes('', registry), isEmpty);
      expect(suggestNirNodeTypes('   ', registry), isEmpty);
    });

    test('exact display-name match comes first', () {
      final results = suggestNirNodeTypes('Synapse', registry);
      expect(results.first.id, 'nir.synapse');
    });

    test('case-insensitive prefix match works', () {
      final results = suggestNirNodeTypes('lif', registry);
      // Both LIF Neuron entries should appear
      expect(results.any((t) => t.id == 'nir.lif'), isTrue);
      expect(results.any((t) => t.id == 'nir.lifr'), isTrue);
    });

    test('prefix match precedes substring match', () {
      // 'pop' is a prefix of 'Population'
      final results = suggestNirNodeTypes('pop', registry);
      expect(results.first.displayName, contains('Population'));
    });

    test('fuzzy match tolerates "Sinaps" → Synapse', () {
      // Use generous maxDistance since full display name is longer
      final results = suggestNirNodeTypes('Sinaps', registry, maxDistance: 6);
      expect(results.any((t) => t.id == 'nir.synapse'), isTrue);
    });

    test('fuzzy match tolerates "LI F" → LIF (generous threshold)', () {
      // "LI F" vs "LIF Neuron": distance is > 4 for full name;
      // with threshold 8 the fuzzy phase picks it up.
      final results = suggestNirNodeTypes('LI F', registry, maxDistance: 8);
      expect(results.any((t) => t.id.contains('lif')), isTrue);
    });

    test('fuzzy match tolerates "liff" → LIF (generous threshold)', () {
      final results = suggestNirNodeTypes('liff', registry, maxDistance: 8);
      expect(results.any((t) => t.id.contains('lif')), isTrue);
    });

    test('respects max cap', () {
      final results = suggestNirNodeTypes('l', registry, max: 2);
      expect(results.length, lessThanOrEqualTo(2));
    });

    test('returns at most max results for broad match', () {
      final results = suggestNirNodeTypes('neuron', registry, max: 1);
      expect(results.length, equals(1));
    });

    test('no duplicates in results', () {
      final results = suggestNirNodeTypes('lif', registry);
      final ids = results.map((t) => t.id).toList();
      expect(ids.toSet().length, equals(ids.length));
    });

    test('very dissimilar input returns empty with default threshold', () {
      // 'zzzzz' should not match anything within distance 4
      final results = suggestNirNodeTypes('zzzzz', registry);
      expect(results, isEmpty);
    });
  });
}
