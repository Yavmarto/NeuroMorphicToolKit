import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/kubernetes_deployment.dart';

DeploymentRequest _request(String kubeconfig) => DeploymentRequest(
  targetType: 'kubernetes_cluster',
  mode: 'kubernetes',
  displayName: 'Cluster',
  kubeconfig: kubeconfig,
);

String _configWithUser(String userYaml) =>
    '''
apiVersion: v1
kind: Config
current-context: nmtk
clusters:
  - name: cluster
    cluster:
      server: https://cluster.example.test
contexts:
  - name: nmtk
    context:
      cluster: cluster
      user: deployer
users:
  - name: deployer
    user:
$userYaml
''';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('parses bearer-token kubeconfig without exposing the token', () async {
    final info = await const KubernetesDeploymentService().inspectKubeconfig(
      _request(_configWithUser('      token: secret-token')),
    );

    expect(info.server, Uri.parse('https://cluster.example.test'));
    expect(info.usesBearerToken, isTrue);
    expect(info.usesClientCertificate, isFalse);
    expect(info.toString(), isNot(contains('secret-token')));
  });

  test('parses embedded client certificate credentials', () async {
    final certificate = base64Encode(utf8.encode('certificate'));
    final key = base64Encode(utf8.encode('private-key'));
    final info = await const KubernetesDeploymentService().inspectKubeconfig(
      _request(
        _configWithUser(
          '      client-certificate-data: $certificate\n'
          '      client-key-data: $key',
        ),
      ),
    );

    expect(info.usesBearerToken, isFalse);
    expect(info.usesClientCertificate, isTrue);
  });

  test('mobile rejects kubeconfig exec authentication actionably', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await expectLater(
      const KubernetesDeploymentService().inspectKubeconfig(
        _request(
          _configWithUser(
            '      exec:\n'
            '        command: cloud-login\n'
            '        args: []',
          ),
        ),
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('static token or client certificate'),
        ),
      ),
    );
  });

  test('desktop accepts kubeconfig exec token authentication', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final info = await const KubernetesDeploymentService().inspectKubeconfig(
      _request(
        _configWithUser(
          '      exec:\n'
          '        command: /usr/bin/printf\n'
          '        args:\n'
          '          - "%s"\n'
          '          - \'{"status":{"token":"exec-token"}}\'',
        ),
      ),
    );

    expect(info.usesBearerToken, isTrue);
    expect(info.toString(), isNot(contains('exec-token')));
  });
}
