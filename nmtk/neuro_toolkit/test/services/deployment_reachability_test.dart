import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/deployment_health_checker.dart';
import 'package:neuro_toolkit/services/deployment/deployment_persistence.dart';
import 'package:neuro_toolkit/services/deployment/job_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deployment/client_deployment_test_fakes.dart';

/// The remote overlay publishes every port on the server's own loopback, so
/// nothing on the deployed host answers on its LAN address. A probe sent
/// there cannot connect at all, and the finished install reported "the
/// backend started, but this Mac cannot reach it" with a reinstall as the
/// only way forward.
void main() {
  const target = DeploymentTarget(
    id: 'remote-192-168-2-90',
    displayName: 'Dev backend',
    targetType: 'remote_host',
    mode: 'podman',
    authMode: 'ssh_password',
    host: '203.0.113.90',
    backendPort: 9000,
  );

  Future<List<Uri>> probedUris({required BackendEndpoints? endpoints}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final seen = <Uri>[];
    final checker = DeploymentHealthChecker(
      httpClient: MockClient((request) async {
        seen.add(request.url);
        if (request.url.path == '/api/launcher/modules/neurocnl') {
          return http.Response(jsonEncode(<String, dynamic>{'status': 4}), 200);
        }
        if (request.url.path == '/api/launcher/modules') {
          return http.Response(
            jsonEncode(<dynamic>[
              <String, dynamic>{'id': 'neurocnl'},
            ]),
            200,
          );
        }
        if (request.url.path == '/api/launcher/settings') {
          return http.Response(jsonEncode(<String, dynamic>{}), 200);
        }
        return http.Response(jsonEncode(<String, dynamic>{'status': 'ok'}), 200);
      }),
    );
    final registry = JobRegistry(
      persistenceFactory: () async => DeploymentPersistence(
        preferences: await SharedPreferences.getInstance(),
        secureStorage: MemorySecretStorage(),
      ),
    );
    await checker.verifyRemoteApis(
      const DeploymentJob(
        id: 'job',
        targetId: 'remote-192-168-2-90',
        mode: 'podman',
        stage: 'verifying_suite_api',
        percent: 90,
        stageLabel: 'Verifying',
        logs: <String>[],
      ),
      target,
      attempts: 1,
      adminToken: 'token',
      endpoints: endpoints,
      registry: registry,
    );
    return seen;
  }

  test('tunnelled endpoints keep every probe off the server address', () async {
    final seen = await probedUris(
      endpoints: BackendEndpoints(
        suiteApi: Uri.parse('http://127.0.0.1:51000'),
        launcherControl: Uri.parse('http://127.0.0.1:51001'),
        jupyter: Uri.parse('http://127.0.0.1:51002'),
      ),
    );

    expect(seen, isNotEmpty);
    expect(
      seen.map((uri) => uri.host),
      everyElement('127.0.0.1'),
      reason: 'a loopback-bound backend never answers on ${target.host}',
    );
    // Each service must be reached on its own forwarded port, not on the
    // remote port number it happens to use inside the server.
    expect(
      seen.firstWhere((uri) => uri.path == '/api/suite/health').port,
      51000,
    );
    expect(seen.firstWhere((uri) => uri.path == '/health').port, 51001);
    expect(seen.firstWhere((uri) => uri.path == '/api/status').port, 51002);
  });

  test('without a tunnel the probes fall back to host and port', () async {
    final seen = await probedUris(endpoints: null);

    expect(seen.map((uri) => uri.host), everyElement(target.host));
    expect(
      seen.firstWhere((uri) => uri.path == '/api/suite/health').port,
      target.backendPort,
    );
    expect(seen.firstWhere((uri) => uri.path == '/api/status').port, 8008);
  });
}
