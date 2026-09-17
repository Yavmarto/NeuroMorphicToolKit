import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/nir_node_type_resolver.dart';

NirNodeType _type(String id, String displayName) => NirNodeType(
  id: id,
  displayName: displayName,
  category: 'test',
  icon: Icons.circle,
  ports: const [],
  parameters: const [],
);

void main() {
  final Map<String, NirNodeType> registry = {
    for (final t in [
      _type('nir.LIF', 'LIF'),
      _type('nir.CubaLIF', 'CubaLIF'),
      _type('nir.Input', 'Input'),
      _type('nir.Conv2d', 'Conv2d'),
      _type('cnl.Leaky', 'Leaky (β)'),
      _type('cnl.Dropout', 'Dropout'),
    ])
      t.id: t,
  };

  group('resolveNirNodeType', () {
    test('every registry entry resolves from its own displayName', () {
      for (final type in registry.values) {
        expect(resolveNirNodeType(type.displayName, registry), same(type));
      }
    });

    test('every registry entry resolves from its own id', () {
      for (final type in registry.values) {
        expect(resolveNirNodeType(type.id, registry), same(type));
      }
    });

    test('matches id without the nir./cnl. prefix', () {
      expect(resolveNirNodeType('LIF', registry)!.id, 'nir.LIF');
      expect(resolveNirNodeType('Dropout', registry)!.id, 'cnl.Dropout');
    });

    test('is case-insensitive', () {
      expect(resolveNirNodeType('lif', registry)!.id, 'nir.LIF');
      expect(resolveNirNodeType('CONV2D', registry)!.id, 'nir.Conv2d');
    });

    test('matches on displayName prefix', () {
      expect(resolveNirNodeType('Cuba', registry)!.id, 'nir.CubaLIF');
    });

    test('matches on displayName substring', () {
      expect(resolveNirNodeType('eaky', registry)!.id, 'cnl.Leaky');
    });

    test('fuzzy-matches minor handwriting-recognition typos', () {
      // "LlF" (lowercase L mis-recognized in place of I) is edit-distance 1 from "lif".
      expect(resolveNirNodeType('LlF', registry)!.id, 'nir.LIF');
    });

    test('returns null for empty or unrelated input', () {
      expect(resolveNirNodeType('', registry), isNull);
      expect(resolveNirNodeType('   ', registry), isNull);
      expect(resolveNirNodeType('zzzzzzzzzz', registry), isNull);
    });
  });
}
