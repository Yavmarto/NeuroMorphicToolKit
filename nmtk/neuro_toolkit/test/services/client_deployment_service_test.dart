import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/deployment/client_deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';

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
}
