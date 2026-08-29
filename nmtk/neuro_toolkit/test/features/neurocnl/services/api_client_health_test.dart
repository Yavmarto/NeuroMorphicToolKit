import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';

void main() {
  test('health uses suite-style api base directly', () async {
    late Uri requestedUri;
    final client = ApiClient(
      baseUrl: 'http://localhost:9000/api/neurocnl',
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        return http.Response('{"status":"ok","mujoco_available":false}', 200);
      }),
    );

    await client.health();

    expect(
      requestedUri.toString(),
      'http://localhost:9000/api/neurocnl/health',
    );
  });

  test('health strips standalone /api suffix', () async {
    late Uri requestedUri;
    final client = ApiClient(
      baseUrl: 'http://localhost:8000/api',
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        return http.Response('{"status":"ok","mujoco_available":false}', 200);
      }),
    );

    await client.health();

    expect(requestedUri.toString(), 'http://localhost:8000/health');
  });
}
