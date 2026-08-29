import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/services/pipeline_workflow_service.dart';

import '../providers_test.mocks.dart';

const _parseResult = ParseResult(sentences: [], total: 0, errors: 0);
const _validationResult = ValidationResult(
  layer1: Layer1Result(overall: true, passed: [], failed: []),
  layer2: Layer2Result(
    overall: true,
    checksPassed: [],
    checksFailed: [],
    neuronsFound: [],
  ),
  overall: true,
  backendSupport: BackendSupportResult(backend: 'nir', verdict: 'approximate'),
);

void main() {
  group('PipelineWorkflowService', () {
    test('runs parse before validation and reports both results', () async {
      final api = MockApiClient();
      final service = PipelineWorkflowService(api);
      final received = <Object>[];
      when(api.parse('spec')).thenAnswer((_) async => _parseResult);
      when(
        api.validate('spec', backend: 'nir'),
      ).thenAnswer((_) async => _validationResult);

      await service.parseAndValidate(
        spec: 'spec',
        backend: 'nir',
        onParsed: received.add,
        onValidated: received.add,
      );

      expect(received, [_parseResult, _validationResult]);
      verifyInOrder([api.parse('spec'), api.validate('spec', backend: 'nir')]);
    });

    test('stops before validation when parsing fails', () async {
      final api = MockApiClient();
      final service = PipelineWorkflowService(api);
      when(api.parse('bad spec')).thenThrow(StateError('parse error'));

      await expectLater(
        service.parseAndValidate(
          spec: 'bad spec',
          backend: 'nir',
          onParsed: (_) {},
          onValidated: (_) {},
        ),
        throwsA(
          isA<PipelineWorkflowFailure>().having(
            (failure) => failure.stage,
            'stage',
            PipelineWorkflowStage.parse,
          ),
        ),
      );
      verifyNever(api.validate(any, backend: anyNamed('backend')));
    });
  });
}
