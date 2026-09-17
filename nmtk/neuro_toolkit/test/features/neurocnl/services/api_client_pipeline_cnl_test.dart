import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';

void main() {
  group('ApiClient.generatePipelineCnl', () {
    test('posts pipeline_config and parses cnl_text/diagnostics', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/notebook/generate-pipeline-cnl');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['pipeline_config'], {'epochs': 5});
        return http.Response(
          jsonEncode({
            'cnl_text': 'Train the network for 5 epochs.',
            'diagnostics': <String>[],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = ApiClient(baseUrl: 'http://test/api', httpClient: client);

      final result = await api.generatePipelineCnl({'epochs': 5});

      expect(result.cnlText, 'Train the network for 5 epochs.');
      expect(result.diagnostics, isEmpty);
    });
  });

  group('ApiClient.parsePipelineCnl', () {
    test('posts cnl_text and pipeline_config, parses merged config', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/notebook/parse-pipeline-cnl');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['cnl_text'], 'Train the network for 7 epochs.');
        expect(body['pipeline_config'], {'epochs': 50});
        return http.Response(
          jsonEncode({
            'pipeline_config': {'epochs': 7, 'optimizer': 'Adam'},
            'diagnostics': <String>[],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = ApiClient(baseUrl: 'http://test/api', httpClient: client);

      final result = await api.parsePipelineCnl(
        'Train the network for 7 epochs.',
        {'epochs': 50},
      );

      expect(result.pipelineConfig.epochs, 7);
    });

    test('a 422 response throws ApiException', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'unknown_optimizer_phrase'}),
          422,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = ApiClient(baseUrl: 'http://test/api', httpClient: client);

      expect(
        () => api.parsePipelineCnl('Train the network for 5 epochs.', {}),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('ApiClient.generateNotebookV2 pipelineCnl argument', () {
    test('omits pipeline_cnl from body when null or empty', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('pipeline_cnl'), isFalse);
        return http.Response(
          jsonEncode({
            'workspace_folder': 'ws',
            'notebooks': <Map<String, dynamic>>[],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = ApiClient(baseUrl: 'http://test/api', httpClient: client);

      await api.generateNotebookV2(
        spec: 'Define a network named demo.',
        pipelineConfig: const {},
      );
      await api.generateNotebookV2(
        spec: 'Define a network named demo.',
        pipelineConfig: const {},
        pipelineCnl: '',
      );
    });

    test('includes pipeline_cnl in body when non-empty', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['pipeline_cnl'], 'Train the network for 5 epochs.');
        return http.Response(
          jsonEncode({
            'workspace_folder': 'ws',
            'notebooks': <Map<String, dynamic>>[],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = ApiClient(baseUrl: 'http://test/api', httpClient: client);

      await api.generateNotebookV2(
        spec: 'Define a network named demo.',
        pipelineConfig: const {},
        pipelineCnl: 'Train the network for 5 epochs.',
      );
    });
  });

  group('ApiClient.generateNotebookV2 importId argument', () {
    test('includes import_id in body when non-empty', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['import_id'], 'nir-import-123');
        return http.Response(
          jsonEncode({
            'workspace_folder': 'ws',
            'notebooks': <Map<String, dynamic>>[],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = ApiClient(baseUrl: 'http://test/api', httpClient: client);

      await api.generateNotebookV2(
        spec: 'Define a network named demo.',
        pipelineConfig: const {},
        importId: 'nir-import-123',
      );
    });
  });
}
