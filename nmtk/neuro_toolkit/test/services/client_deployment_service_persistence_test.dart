import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/bootstrap_transcript_parsing.dart';
import 'package:neuro_toolkit/services/deployment/client_deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/deployment_persistence.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/remote_deployment_runner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deployment/client_deployment_test_fakes.dart';

void main() {
  test('a progress heartbeat does not look like real progress', () {
    final job = DeploymentJob(
      id: 'job',
      targetId: 'remote',
      mode: 'podman',
      stage: 'bootstrapping_access',
      percent: 17,
      stageLabel: 'Preparing the NMTK deployment account',
      logs: const <String>[],
      updatedAt: DateTime.utc(2026, 7, 29, 10),
      lastProgressAt: DateTime.utc(2026, 7, 29, 10),
    );

    // What the 5-second liveness heartbeat does: refresh updatedAt only.
    final heartbeat = job.copyWith(updatedAt: DateTime.utc(2026, 7, 29, 10, 5));
    expect(heartbeat.lastProgressAt, DateTime.utc(2026, 7, 29, 10));
    expect(heartbeat.updatedAt, DateTime.utc(2026, 7, 29, 10, 5));

    final restored = DeploymentJob.fromJson(heartbeat.toJson());
    expect(restored.lastProgressAt, DateTime.utc(2026, 7, 29, 10));
  });

  test('deployment failure details survive job persistence JSON', () {
    final operationStartedAt = DateTime.utc(2026, 7, 29, 10, 30);
    final original = DeploymentJob(
      id: 'job',
      targetId: 'remote',
      mode: 'docker',
      stage: 'failed',
      percent: 100,
      stageLabel: 'Podman installations could not be inspected',
      logs: <String>['Checking Podman'],
      terminalOutput: <String>[
        r'$ podman info',
        '✗ podman info failed (exit 125)',
      ],
      requiresEphemeralAdministrator: true,
      failureDetails: const DeploymentFailureDetails(
        code: 'podman_inspection_failed',
        phase: 'reconciling_existing_install',
        summary: 'Podman installations could not be inspected',
        recovery: 'Check Podman access and retry.',
        technicalDetails: 'podman info failed',
        exitCode: 29,
        existingConnectionReachable: true,
      ),
      activeOperation: DeploymentActiveOperation(
        label: 'Verifying rootless Podman API',
        startedAt: operationStartedAt,
        timeoutSeconds: 20,
        automaticRecovery: true,
      ),
    );

    final restored = DeploymentJob.fromJson(original.toJson());

    expect(restored.failureDetails?.code, 'podman_inspection_failed');
    expect(restored.failureDetails?.exitCode, 29);
    expect(restored.failureDetails?.existingConnectionReachable, isTrue);
    expect(restored.terminalOutput, contains(r'$ podman info'));
    expect(restored.requiresEphemeralAdministrator, isTrue);
    expect(restored.activeOperation?.label, 'Verifying rootless Podman API');
    expect(restored.activeOperation?.startedAt, operationStartedAt);
    expect(restored.activeOperation?.timeoutSeconds, 20);
    expect(restored.activeOperation?.automaticRecovery, isTrue);
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

    final redacted = redactForLogging(
      'password-secret private-key-secret kubeconfig-secret',
      request,
    );

    expect(redacted, isNot(contains('password-secret')));
    expect(redacted, isNot(contains('private-key-secret')));
    expect(redacted, isNot(contains('kubeconfig-secret')));
    expect(redacted, '[redacted] [redacted] [redacted]');
  });

  test(
    'saving a remote target replaces older records for the same IP',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final persistence = DeploymentPersistence(
        preferences: await SharedPreferences.getInstance(),
        secureStorage: MemorySecretStorage(),
      );
      const request = DeploymentRequest(
        targetType: 'remote_host',
        mode: 'docker',
        displayName: 'Remote',
        host: '192.168.2.34',
        username: 'nmtk-deploy',
        sshPrivateKey: 'generated-deploy-key',
      );
      for (final id in ['old-attempt', 'remote-192-168-2-34']) {
        await persistence.saveTarget(
          DeploymentTarget(
            id: id,
            displayName: 'Remote',
            targetType: 'remote_host',
            mode: 'docker',
            authMode: 'ssh_key',
            host: '192.168.2.34',
            username: 'nmtk-deploy',
            backendPort: 9000,
          ),
          request,
        );
      }

      final targets = await persistence.loadTargets();
      expect(targets, hasLength(1));
      expect(targets.single.id, 'remote-192-168-2-34');
    },
  );

  test('relinking SSH credentials preserves an existing admin token', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final secrets = MemorySecretStorage();
    final persistence = DeploymentPersistence(
      preferences: await SharedPreferences.getInstance(),
      secureStorage: secrets,
    );
    const host = '192.168.2.90';
    const targetId = 'remote-192-168-2-90';
    await persistence.saveTarget(
      const DeploymentTarget(
        id: targetId,
        displayName: 'Dev backend',
        targetType: 'remote_host',
        mode: 'docker',
        authMode: 'ssh_key',
        host: host,
        backendPort: 9000,
      ),
      const DeploymentRequest(
        targetType: 'remote_host',
        mode: 'docker',
        displayName: 'Dev backend',
        host: host,
        adminToken: 'previously-issued-token',
      ),
    );

    final service = ClientDeploymentService(
      persistenceFactory: () async => persistence,
    );
    await service.linkExistingTarget(
      const DeploymentRequest(
        targetType: 'remote_host',
        mode: 'docker',
        displayName: 'Dev backend',
        host: host,
        username: 'moosebun2',
        sshPassword: 'updated-password',
      ),
    );

    final target = (await persistence.loadTargets()).singleWhere(
      (candidate) => candidate.id == targetId,
    );
    final request = await persistence.requestForTarget(target);
    expect(request.adminToken, 'previously-issued-token');
    expect(request.sshPassword, 'updated-password');
  });

  test(
    'relinking keeps the deployment account the backend runs under',
    () async {
      // Adopting the operator's own login as the target's identity sent every
      // later stack operation to that user's home and container store, where it
      // built a second stack that collided with the real one on its ports.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final persistence = DeploymentPersistence(
        preferences: await SharedPreferences.getInstance(),
        secureStorage: MemorySecretStorage(),
      );
      const host = '192.168.2.90';
      const targetId = 'remote-192-168-2-90';
      await persistence.saveTarget(
        const DeploymentTarget(
          id: targetId,
          displayName: 'Dev backend',
          targetType: 'remote_host',
          mode: 'podman',
          authMode: 'ssh_key',
          host: host,
          username: 'nmtk-deploy',
          backendPort: 9000,
        ),
        const DeploymentRequest(
          targetType: 'remote_host',
          mode: 'podman',
          displayName: 'Dev backend',
          host: host,
          username: 'nmtk-deploy',
          authMethod: 'ssh_key',
          sshPrivateKey: 'deploy-key',
          adminToken: 'issued-token',
        ),
      );

      final service = ClientDeploymentService(
        persistenceFactory: () async => persistence,
      );
      await service.linkExistingTarget(
        const DeploymentRequest(
          targetType: 'remote_host',
          mode: 'podman',
          displayName: 'Dev backend',
          host: host,
          username: 'moosebun2',
          authMethod: 'ssh_password',
          sshPassword: 'operator-password',
        ),
      );

      final target = (await persistence.loadTargets()).singleWhere(
        (candidate) => candidate.id == targetId,
      );
      final request = await persistence.requestForTarget(target);
      expect(target.username, 'nmtk-deploy');
      expect(request.username, 'nmtk-deploy');
      expect(request.sshPrivateKey, 'deploy-key');
      // The entered credential is still kept, for the privileged steps that
      // genuinely need it.
      expect(request.sshPassword, 'operator-password');
    },
  );

  test(
    'relinking replaces a stale token with the one the server accepts',
    () async {
      // An install that failed after generating a token leaves this app pinned
      // to a token the running backend never adopted. Reusing it authenticates
      // as nobody, and the only offered way out was a reinstall.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final persistence = DeploymentPersistence(
        preferences: await SharedPreferences.getInstance(),
        secureStorage: MemorySecretStorage(),
      );
      const host = '192.168.2.90';
      const targetId = 'remote-192-168-2-90';
      await persistence.saveTarget(
        const DeploymentTarget(
          id: targetId,
          displayName: 'Dev backend',
          targetType: 'remote_host',
          mode: 'docker',
          authMode: 'ssh_password',
          host: host,
          backendPort: 9000,
        ),
        const DeploymentRequest(
          targetType: 'remote_host',
          mode: 'docker',
          displayName: 'Dev backend',
          host: host,
          adminToken: 'token-from-a-failed-install',
        ),
      );

      final service = ClientDeploymentService(
        persistenceFactory: () async => persistence,
        runner: const RecoveringRunner('token-the-live-backend-accepts'),
      );
      await service.linkExistingTarget(
        const DeploymentRequest(
          targetType: 'remote_host',
          mode: 'docker',
          displayName: 'Dev backend',
          host: host,
          username: 'moosebun2',
          sshPassword: 'login-password',
        ),
      );

      final target = (await persistence.loadTargets()).singleWhere(
        (candidate) => candidate.id == targetId,
      );
      final request = await persistence.requestForTarget(target);
      expect(request.adminToken, 'token-the-live-backend-accepts');
    },
  );
}

/// Stands in for a server that still holds a usable administrator token.
class RecoveringRunner extends RemoteDeploymentRunner {
  const RecoveringRunner(this.token);

  final String token;

  @override
  Future<String> readExistingAdminToken(
    DeploymentRequest request,
    DeploymentPersistence persistence,
  ) async => token;
}
