import 'dart:async';
import 'dart:convert';

import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/administrator_session.dart';
import 'package:neuro_toolkit/services/deployment/bootstrap_transcript_parsing.dart';
import 'package:neuro_toolkit/services/deployment/deployment_asset_bundle.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/job_registry.dart';
import 'package:neuro_toolkit/services/deployment/remote_bootstrap_script.dart';
import 'package:neuro_toolkit/services/deployment/ssh_deployment_service.dart';

/// Bootstraps a brand-new remote host: proves administrator access, creates
/// the unprivileged `nmtk-deploy` account, and hands the resulting job off to
/// the deployment dispatcher. Talking to a host that's already provisioned
/// is [RemoteDeploymentRunner]'s job, not this class's.
class RemoteServerProvisioner {
  RemoteServerProvisioner({
    SshDeploymentService ssh = const SshDeploymentService(),
    AdministratorSessionManager? adminSessions,
  }) : _ssh = ssh,
       _adminSessions = adminSessions ?? AdministratorSessionManager();

  final SshDeploymentService _ssh;
  final AdministratorSessionManager _adminSessions;

  static const String _releaseImageTag = 'latest';

  /// Kills the in-progress administrator bootstrap session for [jobId], if
  /// any. Returns whether one was found and cancelled.
  bool cancelAdministratorSession(String jobId) => _adminSessions.cancel(jobId);

  Future<RemoteUserBootstrapResult> bootstrapRemoteUser({
    required String host,
    required int sshPort,
    required String rootUsername,
    required String rootPassword,
    required String rootPrivateKey,
    required String containerEngine,
    required JobRegistry registry,
  }) {
    return _bootstrapRemoteUser(
      host: host,
      sshPort: sshPort,
      rootUsername: rootUsername,
      rootPassword: rootPassword,
      rootPrivateKey: rootPrivateKey,
      containerEngine: containerEngine,
      reinstallMode: RemoteReinstallMode.preserveData,
      jobId: _newId('bootstrap'),
      registry: registry,
    );
  }

  Future<DeploymentJob> setupRemoteServer(
    RemoteServerSetupRequest request, {
    required JobRegistry registry,
    required Future<DeploymentAssetBundle> Function() loadBundle,
    required Future<void> Function(
      DeploymentJob job,
      DeploymentTarget target,
      DeploymentRequest request,
      DeploymentAssetBundle bundle,
    )
    runDeployment,
    required Future<bool> Function(DeploymentTarget target) isApiReady,
  }) async {
    final host = _canonicalIpv4(request.host);
    if (host == null) {
      throw const FormatException(
        'Enter a valid IPv4 address, for example 192.168.2.34.',
      );
    }
    if (request.adminUsername.trim().isEmpty) {
      throw const FormatException('Enter the administrator username.');
    }
    if (request.adminPassword.isEmpty && request.adminPrivateKey.isEmpty) {
      throw const FormatException(
        'Enter the administrator password or SSH private key.',
      );
    }
    if (request.containerEngine != 'docker' &&
        request.containerEngine != 'podman') {
      throw const FormatException('Remote setup supports Docker or Podman.');
    }

    final bundle = await loadBundle();
    final targetId = 'remote-${host.replaceAll('.', '-')}';
    final jobId = _newId('deploy');
    final target = DeploymentTarget(
      id: targetId,
      displayName: 'NMTK server $host',
      targetType: 'remote_host',
      mode: 'docker',
      authMode: 'ssh_key',
      host: host,
      sshPort: request.sshPort,
      username: 'nmtk-deploy',
      backendPort: 9000,
      containerEngine: request.containerEngine,
      updatedAt: DateTime.now(),
    );
    final job = DeploymentJob(
      id: jobId,
      targetId: targetId,
      mode: 'docker',
      stage: DeploymentPhase.queued.wireName,
      percent: 0,
      stageLabel: 'Server setup queued',
      logs: const [],
      terminalOutput: const [],
      requiresEphemeralAdministrator: true,
      bundleVersion: bundle.version,
      bundleManifestHash: bundle.manifestHash,
      imageTag: _releaseImageTag,
      updatedAt: DateTime.now(),
    );
    registry.jobs[jobId] = job;
    registry.pendingTargets[jobId] = target;
    await (await registry.store).saveActiveJob(job);
    registry.runningJobs[jobId] = _runRemoteSetup(
      job,
      target,
      request,
      bundle,
      registry: registry,
      runDeployment: runDeployment,
      isApiReady: isApiReady,
    );
    unawaited(
      registry.runningJobs[jobId]!.whenComplete(() {
        registry.runningJobs.remove(jobId);
      }),
    );
    return job;
  }

  Future<void> _runRemoteSetup(
    DeploymentJob job,
    DeploymentTarget target,
    RemoteServerSetupRequest setupRequest,
    DeploymentAssetBundle bundle, {
    required JobRegistry registry,
    required Future<void> Function(
      DeploymentJob job,
      DeploymentTarget target,
      DeploymentRequest request,
      DeploymentAssetBundle bundle,
    )
    runDeployment,
    required Future<bool> Function(DeploymentTarget target) isApiReady,
  }) async {
    final host = target.host;
    try {
      await registry.emit(
        job,
        DeploymentPhase.connecting,
        2,
        'Connecting with administrator access',
      );
      await registry.emit(
        job,
        DeploymentPhase.bootstrappingAccess,
        5,
        'Checking administrator access',
      );
      final bootstrap = await _bootstrapRemoteUser(
        host: host,
        sshPort: setupRequest.sshPort,
        rootUsername: setupRequest.adminUsername.trim(),
        rootPassword: setupRequest.adminPassword,
        rootPrivateKey: setupRequest.adminPrivateKey,
        containerEngine: setupRequest.containerEngine,
        reinstallMode: setupRequest.reinstallMode,
        onPhase: (phase, percent, label) =>
            registry.emit(job, phase, percent, label),
        onOperation: (operation) =>
            registry.setActiveOperation(job.id, operation),
        onTerminalOutput: (line) => registry.appendTerminalOutput(job.id, line),
        jobId: job.id,
        registry: registry,
      );
      final afterBootstrap = registry.jobs[job.id] ?? job;
      if (afterBootstrap.stage == DeploymentPhase.cancelled.wireName) return;
      final handoffJob = afterBootstrap.copyWith(
        stage: DeploymentPhase.connecting.wireName,
        percent: 18,
        stageLabel: 'Connecting with deployment account',
        logs: [...afterBootstrap.logs, 'Connecting with deployment account'],
        requiresEphemeralAdministrator: false,
        clearActiveOperation: true,
        updatedAt: DateTime.now(),
      );
      await registry.updateJob(handoffJob);
      final deploymentRequest = DeploymentRequest(
        targetType: 'remote_host',
        mode: 'docker',
        displayName: target.displayName,
        host: host,
        username: bootstrap.username,
        sshPort: setupRequest.sshPort,
        authMethod: 'ssh_key',
        sshPrivateKey: bootstrap.sshPrivateKey,
        containerEngine: setupRequest.containerEngine,
        cleanInstall:
            setupRequest.reinstallMode == RemoteReinstallMode.factoryReset,
      );
      registry.pendingTargets[job.id] = target;
      registry.pendingRequests[job.id] = deploymentRequest;
      await runDeployment(handoffJob, target, deploymentRequest, bundle);
    } catch (error) {
      final current = registry.jobs[job.id] ?? job;
      if (current.stage == DeploymentPhase.cancelled.wireName) return;
      final failure = await _remoteSetupFailureDetails(
        error,
        target,
        setupRequest,
        current.stage,
        isApiReady: isApiReady,
      );
      await registry.updateJob(
        current.copyWith(
          stage: DeploymentPhase.failed.wireName,
          percent: 100,
          stageLabel: failure.summary,
          logs: [...current.logs, failure.summary],
          error: failure.recovery,
          failureDetails: failure,
          terminalOutput: boundedTerminalOutput([
            ...current.terminalOutput,
            if (current.terminalOutput.isEmpty ||
                !current.terminalOutput.last.startsWith('[client:'))
              '[client: ${failure.summary}]',
            if (failure.technicalDetails.isNotEmpty)
              '[client-detail: ${failure.technicalDetails}]',
          ]),
          requiresEphemeralAdministrator: false,
          clearActiveOperation: true,
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<DeploymentFailureDetails> _remoteSetupFailureDetails(
    Object error,
    DeploymentTarget target,
    RemoteServerSetupRequest request,
    String currentPhase, {
    required Future<bool> Function(DeploymentTarget target) isApiReady,
  }) async {
    final existingConnectionReachable = await isApiReady(target);
    if (error is RemoteSetupException) {
      return error.details.copyWithConnection(existingConnectionReachable);
    }
    final requestForRedaction = DeploymentRequest(
      targetType: 'remote_host',
      mode: 'docker',
      displayName: target.displayName,
      host: target.host,
      username: request.adminUsername,
      sshPort: request.sshPort,
      authMethod: request.adminPrivateKey.isNotEmpty
          ? 'ssh_key'
          : 'ssh_password',
      sshPassword: request.adminPassword,
      sshPrivateKey: request.adminPrivateKey,
      containerEngine: request.containerEngine,
    );
    final detail = boundedDiagnosticOutput(
      redactForLogging(error.toString(), requestForRedaction),
    );
    final friendly = redactForLogging(
      friendlySshError(error),
      requestForRedaction,
    );
    final isAuthentication = friendly.toLowerCase().contains(
      'authentication failed',
    );
    final isHostKeyMismatch = friendly.toLowerCase().contains(
      'does not match the one previously',
    );
    return DeploymentFailureDetails(
      code: isHostKeyMismatch
          ? 'host_key_mismatch'
          : isAuthentication
          ? 'admin_authentication_failed'
          : 'ssh_failed',
      phase: currentPhase,
      summary: isHostKeyMismatch
          ? 'Server identity changed'
          : isAuthentication
          ? 'Administrator authentication failed'
          : 'Could not connect to the server',
      recovery: friendly,
      technicalDetails: detail,
      existingConnectionReachable: existingConnectionReachable,
    );
  }

  Future<RemoteUserBootstrapResult> _bootstrapRemoteUser({
    required String host,
    required int sshPort,
    required String rootUsername,
    required String rootPassword,
    required String rootPrivateKey,
    required String containerEngine,
    required RemoteReinstallMode reinstallMode,
    required String jobId,
    required JobRegistry registry,
    Future<void> Function(DeploymentPhase phase, double percent, String label)?
    onPhase,
    Future<void> Function(DeploymentActiveOperation? operation)? onOperation,
    Future<void> Function(String line)? onTerminalOutput,
  }) async {
    final request = DeploymentRequest(
      targetType: 'remote_host',
      mode: containerEngine,
      displayName: 'Remote backend',
      host: host,
      username: rootUsername,
      sshPort: sshPort,
      authMethod: rootPrivateKey.isNotEmpty ? 'ssh_key' : 'ssh_password',
      sshPassword: rootPassword,
      sshPrivateKey: rootPrivateKey,
      containerEngine: containerEngine,
    );
    final client = await _ssh.connect(
      request: request,
      persistence: await registry.store,
    );
    try {
      final result = await _adminSessions.runScript(
        client,
        script: buildRemoteBootstrapScript(
          containerEngine: containerEngine,
          factoryReset: reinstallMode == RemoteReinstallMode.factoryReset,
        ),
        rootUsername: rootUsername,
        rootPassword: rootPassword,
        onPhase: onPhase,
        onOperation: onOperation,
        onTerminalOutput: onTerminalOutput,
        jobId: jobId,
        redactionSecrets: [rootPassword, rootPrivateKey],
      );
      if (result.exitCode != 0) {
        throw RemoteSetupException(
          bootstrapFailureDetails(
            utf8.decode(result.stderr).trim(),
            exitCode: result.exitCode ?? 1,
            rootPassword: rootPassword,
            rootPrivateKey: rootPrivateKey,
          ),
        );
      }
      final output = utf8.decode(result.stdout);
      final encodedKey = output
          .split('\n')
          .where((line) => line.startsWith('NMTK_DEPLOY_PRIVATE_KEY_B64='))
          .map((line) => line.substring('NMTK_DEPLOY_PRIVATE_KEY_B64='.length))
          .lastOrNull;
      if (encodedKey == null || encodedKey.isEmpty) {
        throw StateError(
          'The server was prepared, but it did not return the generated '
          'deployment credential. Retry setup.',
        );
      }
      return RemoteUserBootstrapResult(
        username: 'nmtk-deploy',
        sshPrivateKey: utf8.decode(base64Decode(encodedKey)),
      );
    } finally {
      await onOperation?.call(null);
      client.close();
    }
  }

  static String? _canonicalIpv4(String value) {
    final parts = value.trim().split('.');
    if (parts.length != 4) return null;
    final normalized = <String>[];
    for (final part in parts) {
      if (part.isEmpty || !RegExp(r'^\d{1,3}$').hasMatch(part)) return null;
      final number = int.tryParse(part);
      if (number == null || number < 0 || number > 255) return null;
      normalized.add(number.toString());
    }
    return normalized.join('.');
  }

  static String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
