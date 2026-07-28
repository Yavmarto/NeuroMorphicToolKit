import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/client_deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/deployment_persistence.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecretStorage implements DeploymentSecretStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

Future<DeploymentPersistence> _completedRemotePersistence() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final persistence = DeploymentPersistence(
    preferences: await SharedPreferences.getInstance(),
    secureStorage: _MemorySecretStorage(),
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
  test('deployment bundle verifies every uploaded asset checksum', () {
    const deploymentFiles = <String>[
      'docker-compose.yml',
      'docker-compose.prod.yml',
      'docker-compose.remote.yml',
      'install.sh',
      'monitoring/alertmanager/alertmanager.yml',
      'monitoring/loki/loki-config.yml',
      'monitoring/prometheus/alert_rules.yml',
      'monitoring/prometheus/prometheus.yml',
      'monitoring/promtail/promtail-config.yml',
    ];
    const checksum =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final bundle = DeploymentAssetBundle.fromManifestBytes(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'bundleVersion': 3,
            'files': {for (final file in deploymentFiles) file: checksum},
          }),
        ),
      ),
    );

    final parsed = DeploymentAssetBundle.parseRemoteChecksumOutput(
      <String>[
        for (final file in deploymentFiles) '$checksum  $file',
        '${bundle.manifestHash}  deployment-manifest.json',
      ].join('\n'),
    );

    expect(
      () => DeploymentAssetBundle.validateRemoteChecksums(
        bundle: bundle,
        actualChecksums: {
          for (final file in deploymentFiles) file: checksum,
          'install.sh': 'different',
          'deployment-manifest.json': bundle.manifestHash,
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('install.sh'),
        ),
      ),
    );
    expect(
      () => DeploymentAssetBundle.validateRemoteChecksums(
        bundle: bundle,
        actualChecksums: {
          for (final file in deploymentFiles) file: checksum,
          'deployment-manifest.json': bundle.manifestHash,
        },
      ),
      returnsNormally,
    );
    expect(parsed, {
      for (final file in deploymentFiles) file: checksum,
      'deployment-manifest.json': bundle.manifestHash,
    });
  });

  test('deployment bundle reports unreadable checksum output separately', () {
    expect(
      () => DeploymentAssetBundle.parseRemoteChecksumOutput(
        'remote command did not produce checksums',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('unreadable output'),
        ),
      ),
    );
  });

  test('redacts every credential type from deployment logs', () {
    const request = DeploymentRequest(
      targetType: 'remote_host',
      mode: 'docker',
      displayName: 'Remote',
      sshPassword: 'password-secret',
      sshPrivateKey: 'private-key-secret',
      kubeconfig: 'kubeconfig-secret',
    );

    final redacted = ClientDeploymentService.redactForLogging(
      'password-secret private-key-secret kubeconfig-secret',
      request,
    );

    expect(redacted, isNot(contains('password-secret')));
    expect(redacted, isNot(contains('private-key-secret')));
    expect(redacted, isNot(contains('kubeconfig-secret')));
    expect(redacted, '[redacted] [redacted] [redacted]');
  });

  test('does not retain completed when this device cannot reach the server',
      () async {
    final service = ClientDeploymentService(
      persistenceFactory: _completedRemotePersistence,
      httpClient:
          MockClient((_) async => throw http.ClientException('offline')),
    );

    final snapshot = await service.load();

    expect(snapshot.isReady, isFalse);
    expect(snapshot.activeJob?.stage, 'failed');
    expect(snapshot.activeJob?.error, contains('cannot reach'));
  });

  test('retains completion only after desktop-visible NeuroStudio readiness',
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
  });
}
