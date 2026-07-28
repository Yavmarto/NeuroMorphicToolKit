import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/deployment/client_deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';

void main() {
  test('deployment bundle verifies every uploaded asset checksum', () {
    final bundle = DeploymentAssetBundle.fromManifestBytes(
      Uint8List.fromList(
        utf8.encode(
          '{"bundleVersion":2,"files":{"install.sh":"abc123"}}',
        ),
      ),
    );

    expect(
      () => DeploymentAssetBundle.validateRemoteChecksums(
        bundle: bundle,
        actualChecksums: {
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
          'install.sh': 'abc123',
          'deployment-manifest.json': bundle.manifestHash,
        },
      ),
      returnsNormally,
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
