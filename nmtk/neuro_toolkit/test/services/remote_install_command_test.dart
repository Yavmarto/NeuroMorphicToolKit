import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/remote_deployment_runner.dart';

void main() {
  test(
    'buildRemoteInstallCommandArgs passes resolved release tag to install.sh',
    () {
      final args = buildRemoteInstallCommandArgs(
        containerEngine: 'docker',
        backendPort: 9000,
        imageTag: '1.4.0',
        cleanInstall: false,
        host: '203.0.113.90',
        statusFile: '/home/nmtk/.nmtk/deploy/.jobs/job-1.status',
        logFile: '/home/nmtk/.nmtk/deploy/.jobs/job-1.log',
      );

      expect(args, [
        'bash',
        'install.sh',
        'docker',
        '9000',
        '1.4.0',
        'false',
        '203.0.113.90',
        '/home/nmtk/.nmtk/deploy/.jobs/job-1.status',
        '/home/nmtk/.nmtk/deploy/.jobs/job-1.log',
      ]);
    },
  );

  test('buildRemoteInstallCommandArgs forwards schema migration flag', () {
    final args = buildRemoteInstallCommandArgs(
      containerEngine: 'podman',
      backendPort: 9000,
      imageTag: '2.0.0',
      cleanInstall: false,
      host: '192.0.2.5',
      statusFile: 'job.status',
      logFile: 'job.log',
      schemaMigration: true,
    );

    expect(args, containsAll(['--schema-migration', 'true']));
    expect(args[4], '2.0.0');
  });

  test(
    'DeploymentRequest.deploymentImageTag prefers releaseVersion over latest',
    () {
      const request = DeploymentRequest(
        targetType: 'remote_host',
        mode: 'docker',
        displayName: 'lab',
        releaseVersion: '1.4.0',
      );

      expect(request.deploymentImageTag, '1.4.0');
    },
  );

  test('DeploymentRequest.deploymentImageTag falls back to latest', () {
    const request = DeploymentRequest(
      targetType: 'remote_host',
      mode: 'docker',
      displayName: 'lab',
    );

    expect(request.deploymentImageTag, 'latest');
  });
}
