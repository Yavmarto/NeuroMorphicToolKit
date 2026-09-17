import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/deploy_readiness_result.dart';

void main() {
  group('DeployReadinessResult', () {
    test('ok constructs and compares equal', () {
      const a = DeployReadinessResult.ok();
      const b = DeployReadinessResult.ok();
      expect(a, equals(b));
      expect(a, isA<DeployReadinessOk>());
    });

    test('unsupported constructs with expected fields', () {
      const result = DeployReadinessResult.unsupported(
        level: 'unsupported',
        unsupportedNodes: ['stdp_synapse'],
        diagnostics: ['STDP not supported on target'],
      );
      expect(result, isA<DeployReadinessUnsupported>());
      final unsupported = result as DeployReadinessUnsupported;
      expect(unsupported.level, 'unsupported');
      expect(unsupported.unsupportedNodes, ['stdp_synapse']);
      expect(unsupported.diagnostics, ['STDP not supported on target']);
    });

    test('unsupported equality is value-based', () {
      const a = DeployReadinessResult.unsupported(
        level: 'approximate',
        unsupportedNodes: ['adaptive_lif'],
        diagnostics: [],
      );
      const b = DeployReadinessResult.unsupported(
        level: 'approximate',
        unsupportedNodes: ['adaptive_lif'],
        diagnostics: [],
      );
      expect(a, equals(b));
    });

    test('unsupported copyWith updates a single field', () {
      const original = DeployReadinessResult.unsupported(
        level: 'approximate',
        unsupportedNodes: ['adaptive_lif'],
        diagnostics: [],
      );
      final updated = (original as DeployReadinessUnsupported).copyWith(
        level: 'unsupported',
      );
      expect(updated.level, 'unsupported');
      expect(updated.unsupportedNodes, ['adaptive_lif']);
    });

    test('error constructs with a message', () {
      const result = DeployReadinessResult.error(message: 'network timeout');
      expect(result, isA<DeployReadinessError>());
      expect((result as DeployReadinessError).message, 'network timeout');
    });

    test('fromJson/toJson round-trips each variant', () {
      const variants = [
        DeployReadinessResult.ok(),
        DeployReadinessResult.unsupported(
          level: 'unsupported',
          unsupportedNodes: ['stdp_synapse'],
          diagnostics: ['STDP not supported on target'],
        ),
        DeployReadinessResult.error(message: 'network timeout'),
      ];
      for (final variant in variants) {
        final json = variant.toJson();
        final decoded = DeployReadinessResult.fromJson(json);
        expect(decoded, equals(variant));
      }
    });
  });
}
