import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_cnl_result.dart';

void main() {
  group('PipelineCnlResult.fromJson()', () {
    test('parses cnl_text and diagnostics', () {
      final result = PipelineCnlResult.fromJson(<String, dynamic>{
        'cnl_text': 'Train the network for 50 epochs.',
        'diagnostics': <String>['note'],
      });
      expect(result.cnlText, 'Train the network for 50 epochs.');
      expect(result.diagnostics, equals(const ['note']));
    });

    test('missing keys fall back to empty defaults', () {
      final result = PipelineCnlResult.fromJson(<String, dynamic>{});
      expect(result.cnlText, '');
      expect(result.diagnostics, isEmpty);
    });
  });

  group('PipelineConfigParseResult.fromJson()', () {
    test('parses nested pipeline_config and diagnostics', () {
      final result = PipelineConfigParseResult.fromJson(<String, dynamic>{
        'pipeline_config': <String, dynamic>{'epochs': 7},
        'diagnostics': <String>['unrecognized field ignored'],
      });
      expect(result.pipelineConfig.epochs, 7);
      expect(result.diagnostics, equals(const ['unrecognized field ignored']));
    });

    test('missing diagnostics falls back to empty list', () {
      final result = PipelineConfigParseResult.fromJson(<String, dynamic>{
        'pipeline_config': <String, dynamic>{},
      });
      expect(result.diagnostics, isEmpty);
      expect(result.pipelineConfig.epochs, 50);
    });
  });
}
