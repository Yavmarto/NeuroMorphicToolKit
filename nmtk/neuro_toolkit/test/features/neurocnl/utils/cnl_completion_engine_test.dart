import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/utils/cnl_completion_engine.dart';

void main() {
  const engine = CnlCompletionEngine();

  // ── Layer 1: template completions ──────────────────────────────────────────

  group('templateCompletions', () {
    test('matches known prefix at start of line', () {
      final results = engine.templateCompletions('The neuron MUST fire');
      expect(results, isNotEmpty);
      expect(
        results.every((c) => c.source == CompletionSource.template),
        isTrue,
      );
    });

    test('case-insensitive matching', () {
      final results = engine.templateCompletions('the neuron must fire');
      expect(results, isNotEmpty);
    });

    test('returns empty for blank input', () {
      expect(engine.templateCompletions(''), isEmpty);
      expect(engine.templateCompletions(' '), isEmpty);
    });

    test('returns empty for non-matching prefix', () {
      final results = engine.templateCompletions('ZZZZZZ');
      expect(results, isEmpty);
    });

    test('respects max cap', () {
      final results = engine.templateCompletions('The', max: 2);
      expect(results.length, lessThanOrEqualTo(2));
    });

    test('all results are templates with MUST or slot marker', () {
      final results = engine.templateCompletions('The');
      for (final c in results) {
        expect(c.source, CompletionSource.template);
        expect(c.text, anyOf(contains('{'), contains('MUST')));
      }
    });
  });

  // ── Layer 2: token completions ─────────────────────────────────────────────

  group('tokenCompletions', () {
    test('completes CNL keyword MUST', () {
      final results = engine.tokenCompletions('MU');
      expect(results.any((c) => c.text == 'MUST'), isTrue);
      expect(results.any((c) => c.text == 'MUST NOT'), isTrue);
    });

    test('completes verb "fire"', () {
      final results = engine.tokenCompletions('fi');
      expect(results.any((c) => c.text == 'fire'), isTrue);
    });

    test('completes unit "seconds"', () {
      final results = engine.tokenCompletions('sec');
      expect(results.any((c) => c.text == 'seconds'), isTrue);
    });

    test('completes adjective "inhibitory"', () {
      final results = engine.tokenCompletions('inh');
      expect(results.any((c) => c.text == 'inhibitory'), isTrue);
    });

    test('all results are tokens', () {
      final results = engine.tokenCompletions('M');
      for (final c in results) {
        expect(c.source, CompletionSource.token);
      }
    });

    test('respects max cap', () {
      final results = engine.tokenCompletions('M', max: 1);
      expect(results.length, lessThanOrEqualTo(1));
    });

    test('empty partial token returns empty', () {
      expect(engine.tokenCompletions(''), isEmpty);
    });

    test('no duplicate tokens', () {
      final results = engine.tokenCompletions('M');
      final texts = results.map((c) => c.text).toList();
      expect(texts.toSet().length, equals(texts.length));
    });
  });

  // ── Layer 3: node-name completions ─────────────────────────────────────────

  group('nodeNameCompletions', () {
    const labels = <String>[
      'Sensory Layer',
      'Motor Ensemble',
      'Inhibitory Interneuron',
      'Input Encoder',
    ];

    test('returns completions after "The"', () {
      final results = engine.nodeNameCompletions('Sen', 'The', labels);
      expect(results.any((c) => c.text == 'Sensory Layer'), isTrue);
    });

    test('returns completions after "from"', () {
      final results = engine.nodeNameCompletions('Mo', 'from', labels);
      expect(results.any((c) => c.text == 'Motor Ensemble'), isTrue);
    });

    test('returns completions after "to"', () {
      final results = engine.nodeNameCompletions('In', 'to', labels);
      expect(results.any((c) => c.text == 'Inhibitory Interneuron'), isTrue);
    });

    test('returns empty when preceding word is NOT a subject position', () {
      final results = engine.nodeNameCompletions('Sen', 'fire', labels);
      expect(results, isEmpty);
    });

    test('all results are node source', () {
      final results = engine.nodeNameCompletions('', 'The', labels);
      for (final c in results) {
        expect(c.source, CompletionSource.node);
      }
    });

    test('respects max cap', () {
      final results = engine.nodeNameCompletions('', 'The', labels, max: 2);
      expect(results.length, lessThanOrEqualTo(2));
    });

    test('case-insensitive match', () {
      final results = engine.nodeNameCompletions('SENSORY', 'The', labels);
      expect(results.any((c) => c.text == 'Sensory Layer'), isTrue);
    });

    test('empty node labels returns empty', () {
      final results = engine.nodeNameCompletions('Sen', 'The', <String>[]);
      expect(results, isEmpty);
    });
  });

  // ── Combined: suggest() ────────────────────────────────────────────────────

  group('suggest()', () {
    const nodeLabels = <String>['Motor Ensemble', 'Input Encoder'];

    test('layer 1 takes priority when template matches', () {
      const text = 'The neuron MUST fire';
      final results = engine.suggest(text, text.length, nodeLabels);
      expect(results.isNotEmpty, isTrue);
      expect(results.first.source, CompletionSource.template);
    });

    test('falls through to layer 2 when no template matches', () {
      // "XMUST" doesn't match any template prefix
      const text = 'XMUST';
      final results = engine.suggest(text, text.length, nodeLabels);
      // No template matches; token "XMUST" has no keyword/verb → empty or token
      // More importantly: it should not crash and must not return templates
      expect(
        results.every((c) => c.source != CompletionSource.template),
        isTrue,
      );
    });

    test('falls through to layer 2 for known keyword prefix', () {
      // "MU" is not a template prefix but IS a keyword prefix
      const text = 'MU';
      final results = engine.suggest(text, text.length, nodeLabels);
      expect(results.any((c) => c.source == CompletionSource.token), isTrue);
      expect(results.any((c) => c.text == 'MUST'), isTrue);
    });

    test('falls through to layer 3 for node names after subject word', () {
      // 'by' is a subject-position word. 'Inp' starts 'Input Encoder'.
      // No CNL template starts with 'by inp', so layer 1 won't fire.
      const text = 'by Inp';
      final results = engine.suggest(text, text.length, nodeLabels);
      expect(results.any((c) => c.source == CompletionSource.node), isTrue);
      expect(results.any((c) => c.text == 'Input Encoder'), isTrue);
    });

    test('returns empty for < 2 non-whitespace chars on line', () {
      final results = engine.suggest('T', 1, nodeLabels);
      expect(results, isEmpty);
    });

    test('handles cursor in mid-text (multiline)', () {
      // Second line is 'by Inp' — same assertion as single-line case.
      const text = 'Line 1\nby Inp';
      final results = engine.suggest(text, text.length, nodeLabels);
      expect(results.any((c) => c.text == 'Input Encoder'), isTrue);
    });

    test('out-of-range cursor returns empty', () {
      expect(engine.suggest('hello', -1, nodeLabels), isEmpty);
      expect(engine.suggest('hello', 999, nodeLabels), isEmpty);
    });
  });
}
