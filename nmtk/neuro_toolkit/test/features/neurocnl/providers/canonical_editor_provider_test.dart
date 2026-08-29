import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart';

void main() {
  test('FidelityAnnotation JSON round-trip', () {
    final ann = const FidelityAnnotation(
      kind: 'advisory',
      concept: 'neuromodulation',
      message: 'Neuromodulation is metadata-only.',
      affects: ['sensory'],
    );
    final restored = FidelityAnnotation.fromJson(ann.toJson());
    expect(restored.kind, 'advisory');
    expect(restored.concept, 'neuromodulation');
    expect(restored.affects, ['sensory']);
  });

  test('CanonicalEditorDocument JSON round-trip preserves irJson', () {
    final doc = const CanonicalEditorDocument(
      irJson: {'populations': <String, dynamic>{}, 'connections': <dynamic>[]},
      cnlText:
          'The network MUST contain an excitatory sensory population of 4 neurons',
    );
    final restored = CanonicalEditorDocument.fromJson(doc.toJson());
    expect(restored.cnlText, doc.cnlText);
    expect(restored.irJson, doc.irJson);
  });

  test(
    'CanonicalEditorDocument.fromJson strips legacy weight value clauses',
    () {
      final restored = CanonicalEditorDocument.fromJson({
        'ir_json': {
          'populations': <String, dynamic>{},
          'connections': <dynamic>[],
        },
        'cnl_text':
            'Define a linear transformation named fc with weight matrix shape '
            '(3, 2) and weight matrix values (0.5, -0.25, 1.25, -1.5).\n'
            'Define a conv named conv with weight kernel shape (1, 1, 3) and '
            'weight kernel values (1.0, 2.0, 3.0).\n',
      });

      expect(restored.cnlText, isNot(contains('weight matrix values')));
      expect(restored.cnlText, isNot(contains('weight kernel values')));
      expect(restored.cnlText, contains('weight matrix shape (3, 2).'));
      expect(restored.cnlText, contains('weight kernel shape (1, 1, 3).'));
    },
  );

  test('CanvasNode JSON round-trip preserves optional fields', () {
    const node = CanvasNode(
      id: 'sensory',
      label: 'Sensory',
      type: 'excitatory',
      size: 4,
      shape: [2, 2],
      threshold: -55.0,
      tau: 20.0,
    );
    final restored = CanvasNode.fromJson(node.toJson());
    expect(restored.id, 'sensory');
    expect(restored.size, 4);
    expect(restored.shape, [2, 2]);
    expect(restored.threshold, -55.0);
    expect(restored.tau, 20.0);
  });

  test('CanvasEdge JSON round-trip preserves connectivity pattern', () {
    const edge = CanvasEdge(
      source: 'sensory',
      target: 'motor',
      polarity: 'excitatory',
      weight: 0.5,
      connectivityPattern: 'all_to_all',
    );
    final restored = CanvasEdge.fromJson(edge.toJson());
    expect(restored.source, 'sensory');
    expect(restored.target, 'motor');
    expect(restored.weight, 0.5);
    expect(restored.connectivityPattern, 'all_to_all');
  });

  test('ParseCnlResponse JSON round-trip', () {
    final response = const ParseCnlResponse(
      document: CanonicalEditorDocument(
        irJson: <String, dynamic>{},
        cnlText: 'test spec',
      ),
      diagnostics: ['warning: unknown token'],
    );
    final restored = ParseCnlResponse.fromJson(response.toJson());
    expect(restored.document.cnlText, 'test spec');
    expect(restored.diagnostics, ['warning: unknown token']);
  });

  test('GenerateCnlCanonicalResponse JSON round-trip', () {
    final response = const GenerateCnlCanonicalResponse(
      cnlText: 'The network MUST contain a sensory population.',
      document: CanonicalEditorDocument(irJson: <String, dynamic>{}),
    );
    final restored = GenerateCnlCanonicalResponse.fromJson(response.toJson());
    expect(restored.cnlText, 'The network MUST contain a sensory population.');
    expect(restored.document.cnlText, '');
  });

  test(
    'GenerateCnlCanonicalResponse.fromJson strips legacy weight value clauses',
    () {
      final restored = GenerateCnlCanonicalResponse.fromJson({
        'cnl_text':
            'Define an affine transformation named fc with weight matrix shape '
            '(2, 2) and weight matrix values (0.5, -0.25, 1.25, -1.5).',
        'document': {
          'ir_json': <String, dynamic>{},
          'cnl_text':
              'Define a convolution named conv with weight kernel shape (1, 1, 2) '
              'and weight kernel values (1.0, 2.0).',
        },
      });

      expect(restored.cnlText, isNot(contains('weight matrix values')));
      expect(restored.cnlText, contains('weight matrix shape (2, 2).'));
      expect(
        restored.document.cnlText,
        isNot(contains('weight kernel values')),
      );
      expect(
        restored.document.cnlText,
        contains('weight kernel shape (1, 1, 2).'),
      );
    },
  );
}
