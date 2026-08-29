// ignore_for_file: inference_failure_on_collection_literal
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';

void main() {
  group('Canvas ApiClient', () {
    test('rewrites neurocnl API base URLs to the merged neurosim prefix', () {
      final api = ApiClient(baseUrl: 'http://localhost:9000/api/neurocnl');
      expect(api.baseUrl, 'http://localhost:9000/api/neurosim');
    });

    test('posts parse-cnl requests to the merged neurosim route', () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'http://localhost:9000/api/neurosim/parse-cnl',
        );
        return http.Response(
          jsonEncode({'nodes': [], 'edges': [], 'metadata': {}}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(
        baseUrl: 'http://localhost:9000/api/neurocnl',
        httpClient: client,
      );

      final graph = await api.parseCnl('A neuron exists.');
      expect(graph.nodes, isEmpty);
      expect(graph.edges, isEmpty);
    });

    test('loads generated custom-node source with typed metadata', () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'http://localhost:9000/api/neurosim/custom-nodes/source',
        );
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['component_id'], 'lif_population');
        expect(body['nir_type'], 'nir.LIF');
        return http.Response(
          jsonEncode({
            'source': 'class MyLif(CustomNode): pass',
            'component_id': 'lif_population',
            'is_custom': false,
            'save_mode': 'create',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = ApiClient(
        baseUrl: 'http://localhost:9000/api/neurocnl',
        httpClient: client,
      );

      final source = await api.fetchCustomNodeSource(
        componentId: 'lif_population',
        nirType: 'nir.LIF',
        displayName: 'LIF',
        category: 'neuron',
        parameters: const {'tau': 0.02},
      );

      expect(source.isCustom, isFalse);
      expect(source.saveMode, 'create');
      expect(source.source, contains('MyLif'));
    });

    test('returns actionable stale-revision conflicts', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'detail':
                'This custom node changed after the editor opened. Reload it.',
          }),
          409,
          headers: {'content-type': 'application/json'},
        ),
      );
      final api = ApiClient(
        baseUrl: 'http://localhost:9000/api/neurocnl',
        httpClient: client,
      );

      await expectLater(
        api.saveCustomNodeSource(
          source: 'source',
          saveAs: false,
          targetComponentId: 'custom_test',
          expectedRevision: 'old',
        ),
        throwsA(
          isA<CanvasSyncException>().having(
            (error) => error.message.toLowerCase(),
            'message',
            contains('reload'),
          ),
        ),
      );
    });
  });
}
