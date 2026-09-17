import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/features/neurobench/services/api_client.dart';

void main() {
  group('ApiClient Integration Tests', () {
    test('ApiClient structure check', () async {
      final apiClient = ApiClient(baseUrl: 'http://localhost:8000');
      expect(apiClient.baseUrl, 'http://localhost:8000');
    });

    test('ApiClient uses NeuroBench API-prefixed endpoints', () async {
      final requestedPaths = <String>[];
      final requestedQueries = <String, Map<String, String>>{};

      final client = MockClient((request) async {
        requestedPaths.add(request.url.path);
        requestedQueries[request.url.path] = request.url.queryParameters;

        switch (request.url.path) {
          case '/api/neurobench/benchmarks':
            return http.Response('[]', 200);
          case '/api/neurobench/benchmarks/test-benchmark':
            return http.Response('''
              {
                "id": "test-benchmark",
                "name": "Test Benchmark",
                "description": "desc",
                "task_type": "classification",
                "input_spec": {"type": "synthetic"},
                "assertions": [],
                "scoring": {
                  "primary_metric": "accuracy",
                  "secondary_metrics": [],
                  "higher_is_better": true,
                  "pass_threshold": 0.8
                },
                "default_params": {},
                "builtin": true
              }
              ''', 200);
          case '/api/neurobench/results':
            return http.Response('[]', 200);
          case '/api/neurobench/results/result-1':
            return http.Response('''
              {
                "id": "result-1",
                "benchmark_id": "test-benchmark",
                "network_spec_hash": "abc123",
                "timestamp": "2026-04-03T00:00:00Z",
                "target_id": null,
                "quantization_bits": null,
                "encoding_method": null,
                "params": {},
                "metrics": {"accuracy": 0.9},
                "spike_data": null,
                "wall_time_seconds": 1.2,
                "seed": 42
              }
              ''', 200);
          case '/api/neurobench/baselines':
            return http.Response('[]', 200);
          case '/api/neurobench/compare/base-1/current-1':
            return http.Response(
              '{"baseline_id":"base-1","current_id":"current-1","metrics":[]}',
              200,
            );
          case '/api/neurobench/compare/export':
            return http.Response('csv-data', 200);
        }

        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(
        baseUrl: 'http://localhost:8003/api/neurobench',
        client: client,
      );

      await apiClient.getBenchmarks();
      await apiClient.getBenchmark('test-benchmark');
      await apiClient.getResults();
      await apiClient.getResult('result-1');
      await apiClient.getBaselines();
      await apiClient.compareResults('base-1', 'current-1');
      final exported = await apiClient.exportDiff(
        'base-1',
        'current-1',
        format: 'csv',
      );

      expect(
        requestedPaths,
        equals([
          '/api/neurobench/benchmarks',
          '/api/neurobench/benchmarks/test-benchmark',
          '/api/neurobench/results',
          '/api/neurobench/results/result-1',
          '/api/neurobench/baselines',
          '/api/neurobench/compare/base-1/current-1',
          '/api/neurobench/compare/export',
        ]),
      );
      expect(
        requestedQueries['/api/neurobench/compare/export'],
        equals({
          'baseline_ids': 'base-1',
          'current_ids': 'current-1',
          'format': 'csv',
        }),
      );
      expect(exported, 'csv-data');
    });
  });
}
