import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/server/provision/provision_notifier.dart';
import 'package:neuro_toolkit/features/server/provision/provision_service.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/job_registry.dart';

class _SucceedingProvisionService extends ProvisionService {
  @override
  Future<ProvisionResult> run({
    required String host,
    required int sshPort,
    required String sudoUsername,
    String sudoPassword = '',
    String sudoPrivateKey = '',
    required String containerEngine,
    RemoteReinstallMode reinstallMode = RemoteReinstallMode.preserveData,
    Map<String, String> moduleEnvironment = const <String, String>{},
    Map<String, String> moduleSecrets = const <String, String>{},
    void Function(DeploymentJob job)? onProgress,
    JobRegistry? registry,
  }) async {
    onProgress?.call(
      DeploymentJob(
        id: 'job-1',
        targetId: 'remote-192-168-2-90',
        mode: 'docker',
        stage: DeploymentPhase.bootstrappingAccess.wireName,
        percent: 5,
        stageLabel: 'Checking administrator access',
        logs: const [],
        terminalOutput: const [],
      ),
    );
    return ProvisionResult(host: host, appUsername: 'admin');
  }
}

class _FailingProvisionService extends ProvisionService {
  @override
  Future<ProvisionResult> run({
    required String host,
    required int sshPort,
    required String sudoUsername,
    String sudoPassword = '',
    String sudoPrivateKey = '',
    required String containerEngine,
    RemoteReinstallMode reinstallMode = RemoteReinstallMode.preserveData,
    Map<String, String> moduleEnvironment = const <String, String>{},
    Map<String, String> moduleSecrets = const <String, String>{},
    void Function(DeploymentJob job)? onProgress,
    JobRegistry? registry,
  }) async {
    throw const RemoteSetupException(
      DeploymentFailureDetails(
        code: 'admin_authentication_failed',
        phase: 'bootstrapping_access',
        summary: 'Administrator authentication failed',
        recovery: 'Check the username and credentials.',
      ),
    );
  }
}

void main() {
  test('provision() streams progress then reports a result', () async {
    final container = ProviderContainer(
      overrides: [
        provisionServiceProvider.overrideWithValue(_SucceedingProvisionService()),
      ],
    );
    addTearDown(container.dispose);

    final states = <ProvisionState>[];
    container.listen(
      provisionNotifierProvider,
      (previous, next) => states.add(next),
      fireImmediately: true,
    );

    await container
        .read(provisionNotifierProvider.notifier)
        .provision(
          const ProvisionRequest(
            host: '203.0.113.90',
            sudoUser: 'dev',
            credential: ProvisionCredential.password('secret'),
            engine: 'docker',
          ),
        );

    expect(states.first.isRunning, isFalse);
    expect(states.any((s) => s.isRunning && s.phaseLabel != null), isTrue);
    expect(states.any((s) => s.progress != null), isTrue);

    final finalState = container.read(provisionNotifierProvider);
    expect(finalState.isRunning, isFalse);
    expect(finalState.failure, isNull);
    expect(finalState.result?.host, '203.0.113.90');
    expect(finalState.result?.appUsername, 'admin');
  });

  test('provision() reports a plain-English, retryable failure', () async {
    final container = ProviderContainer(
      overrides: [
        provisionServiceProvider.overrideWithValue(_FailingProvisionService()),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(provisionNotifierProvider.notifier)
        .provision(
          const ProvisionRequest(
            host: '203.0.113.90',
            sudoUser: 'dev',
            credential: ProvisionCredential.password('wrong'),
            engine: 'docker',
          ),
        );

    final state = container.read(provisionNotifierProvider);
    expect(state.isRunning, isFalse);
    expect(state.result, isNull);
    expect(state.failure, isNotNull);
    expect(state.failure!.cause, 'Check the username and credentials.');
    expect(state.failure!.retryable, isTrue);
  });
}
