import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/client_deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/deployment_persistence.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deployment/client_deployment_test_fakes.dart';

Future<DeploymentPersistence> _completedRemotePersistence() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final persistence = DeploymentPersistence(
    preferences: await SharedPreferences.getInstance(),
    secureStorage: MemorySecretStorage(),
  );
  const target = DeploymentTarget(
    id: 'remote',
    displayName: 'Remote backend',
    targetType: 'remote_host',
    mode: 'docker',
    authMode: 'ssh_key',
    host: 'server.example',
    backendPort: 9000,
  );
  await persistence.saveTarget(
    target,
    const DeploymentRequest(
      targetType: 'remote_host',
      mode: 'docker',
      displayName: 'Remote backend',
      host: 'server.example',
    ),
  );
  await persistence.saveActiveJob(
    const DeploymentJob(
      id: 'job',
      targetId: 'remote',
      mode: 'docker',
      stage: 'completed',
      percent: 100,
      stageLabel: 'Backend and launcher control are ready',
      logs: <String>[],
    ),
  );
  return persistence;
}

void main() {
  test(
    'does not retain completed when this device cannot reach the server',
    () async {
      final service = ClientDeploymentService(
        persistenceFactory: _completedRemotePersistence,
        httpClient: MockClient(
          (_) async => throw http.ClientException('offline'),
        ),
      );

      final snapshot = await service.load();

      expect(snapshot.isReady, isFalse);
      expect(snapshot.activeJob?.stage, 'failed');
      // The message has to carry the reason: reporting every failed check
      // as "unreachable" hid rejected tokens and modules that would not
      // start behind a network error that was not happening.
      expect(snapshot.activeJob?.error, contains('could not finish checking'));
      expect(
        snapshot.activeJob?.error,
        contains('Suite API did not become ready'),
      );
    },
  );

  test(
    'interrupted setup has no persisted target or deploy credential',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final secrets = MemorySecretStorage();
      final persistence = DeploymentPersistence(
        preferences: await SharedPreferences.getInstance(),
        secureStorage: secrets,
      );
      await persistence.saveActiveJob(
        DeploymentJob(
          id: 'interrupted',
          targetId: 'remote-192-168-2-34',
          mode: 'docker',
          stage: 'uploading_assets',
          percent: 25,
          stageLabel: 'Uploading deployment bundle',
          logs: const <String>[],
          activeOperation: DeploymentActiveOperation(
            label: 'Installing Docker Engine',
            startedAt: DateTime.now(),
            timeoutSeconds: 300,
          ),
        ),
      );
      final service = ClientDeploymentService(
        persistenceFactory: () async => persistence,
      );

      final snapshot = await service.load();

      expect(snapshot.targets, isEmpty);
      expect(secrets.values, isEmpty);
      expect(snapshot.isReady, isFalse);
      expect(snapshot.activeJob?.stage, 'failed');
      expect(snapshot.activeJob?.error, contains('administrator credential'));
      expect(snapshot.activeJob?.activeOperation, isNull);
    },
  );

  test(
    'retains completion only after desktop-visible NeuroStudio readiness',
    () async {
      final service = ClientDeploymentService(
        persistenceFactory: _completedRemotePersistence,
        httpClient: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/launcher/modules/neurocnl/start') {
            return http.Response('{}', 202);
          }
          if (request.url.path == '/api/launcher/modules') {
            return http.Response('[{"id":"neurocnl"}]', 200);
          }
          if (request.url.path == '/api/launcher/modules/neurocnl') {
            return http.Response('{"status":4}', 200);
          }
          return http.Response('{"status":"ok"}', 200);
        }),
      );

      final snapshot = await service.load();

      expect(snapshot.isReady, isTrue);
      expect(snapshot.activeJob?.stage, 'completed');
    },
  );

  test(
    'completed backend verification updates only the selected Akida host',
    () async {
      final requestedPaths = <String>[];
      final service = ClientDeploymentService(
        persistenceFactory: _completedRemotePersistence,
        httpClient: MockClient((request) async {
          requestedPaths.add('${request.method} ${request.url.path}');
          if (request.method == 'POST' &&
              request.url.path == '/api/launcher/modules/neurocnl/start') {
            return http.Response('{}', 202);
          }
          if (request.url.path == '/api/launcher/modules') {
            return http.Response('[{"id":"neurocnl"}]', 200);
          }
          if (request.url.path == '/api/launcher/modules/neurocnl') {
            return http.Response('{"status":4}', 200);
          }
          if (request.url.path == '/api/launcher/settings') {
            return http.Response(
              '{"selectedAkidaHostId":"selected-host"}',
              200,
            );
          }
          if (request.url.path.endsWith('/runtime-update-jobs')) {
            return http.Response(
              '{"jobId":"runtime-job","status":"completed",'
              '"installedVersion":"0.6.0"}',
              202,
            );
          }
          return http.Response('{"status":"ok"}', 200);
        }),
      );

      final snapshot = await service.load();

      expect(snapshot.isReady, isTrue);
      expect(snapshot.activeJob?.error, isEmpty);
      expect(
        requestedPaths,
        contains(
          'POST /api/launcher/akida/hosts/selected-host/runtime-update-jobs',
        ),
      );
      expect(
        requestedPaths.where((path) => path.contains('other-host')),
        isEmpty,
      );
    },
  );

  test(
    'Akida update failure is degraded and preserves core readiness',
    () async {
      final service = ClientDeploymentService(
        persistenceFactory: _completedRemotePersistence,
        httpClient: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/launcher/modules/neurocnl/start') {
            return http.Response('{}', 202);
          }
          if (request.url.path == '/api/launcher/modules') {
            return http.Response('[{"id":"neurocnl"}]', 200);
          }
          if (request.url.path == '/api/launcher/modules/neurocnl') {
            return http.Response('{"status":4}', 200);
          }
          if (request.url.path == '/api/launcher/settings') {
            return http.Response(
              '{"selectedAkidaHostId":"selected-host"}',
              200,
            );
          }
          if (request.url.path.endsWith('/runtime-update-jobs')) {
            return http.Response(
              '{"jobId":"runtime-job","status":"failed",'
              '"message":"The selected Akida host is offline.",'
              '"recovery":"Power it on, then retry."}',
              202,
            );
          }
          return http.Response('{"status":"ok"}', 200);
        }),
      );

      final snapshot = await service.load();

      expect(snapshot.isReady, isTrue);
      expect(snapshot.activeJob?.stage, 'completed');
      expect(
        snapshot.activeJob?.error,
        startsWith('degraded optional capability:'),
      );
      expect(snapshot.activeJob?.error, contains('Akida'));
      expect(snapshot.activeJob?.error, contains('Power it on, then retry.'));
    },
  );

  test('Akida ready never hides a failed backend', () async {
    final service = ClientDeploymentService(
      persistenceFactory: _completedRemotePersistence,
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/suite/doctor') {
          throw http.ClientException('backend down');
        }
        if (request.url.path == '/api/launcher/doctor') {
          return http.Response(
            '{"fatalCount":0,"degradedCount":0,'
            '"akidaHosts":[{"id":"akida-1","state":"ready"}]}',
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );

    final report = await service.diagnoseTarget('remote');

    expect(report.overall, SystemHealthStatus.failed);
    expect(
      report.checks.singleWhere((check) => check.id == 'suite-api').status,
      SystemHealthStatus.failed,
    );
    expect(
      report.checks.singleWhere((check) => check.id == 'akida-runtime').status,
      SystemHealthStatus.ok,
    );
  });
}
