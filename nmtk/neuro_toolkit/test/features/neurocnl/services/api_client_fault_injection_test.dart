import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';

void main() {
  group('ApiClient.prostheticFaultInjection', () {
    test('posts to the backend and parses the response', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/prosthetic/fault-injection');
        return http.Response(
          '''
          {
            "error_rate": 0.1,
            "baseline_accuracy": 0.95,
            "degraded_accuracy": 0.83,
            "failed_nodes": ["sensor"],
            "resilience_score": 0.8737
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(baseUrl: 'http://test', httpClient: client);
      final result = await api.prostheticFaultInjection('spec', 0.1);

      expect(result.errorRate, 0.1);
      expect(result.baselineAccuracy, 0.95);
      expect(result.degradedAccuracy, 0.83);
      expect(result.failedNodes, ['sensor']);
      expect(result.resilienceScore, 0.8737);
    });
  });
}
