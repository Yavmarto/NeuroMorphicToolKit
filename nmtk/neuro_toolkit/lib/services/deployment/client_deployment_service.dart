import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/bootstrap_transcript_parsing.dart';
import 'package:neuro_toolkit/services/backend_tunnel_service.dart';
import 'package:neuro_toolkit/services/deployment/deployment_asset_bundle.dart';
import 'package:neuro_toolkit/services/deployment/deployment_health_checker.dart';
import 'package:neuro_toolkit/services/deployment/deployment_persistence.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/job_registry.dart';
import 'package:neuro_toolkit/services/deployment/kubernetes_deployment.dart';
import 'package:neuro_toolkit/services/deployment/local_deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/remote_deployment_runner.dart';
import 'package:neuro_toolkit/services/deployment/remote_server_provisioner.dart';
import 'package:neuro_toolkit/services/deployment/ssh_deployment_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin orchestrator implementing [DeploymentService]: owns the job registry
/// and dispatches to the collaborator that knows how to do the actual work
/// ([RemoteServerProvisioner] for brand-new hosts, [RemoteDeploymentRunner]
/// for SSH execution against a known target, [DeploymentHealthChecker] for
/// readiness/diagnostics, [LocalDeploymentService]/[KubernetesDeploymentService]
/// for their respective target types).
class ClientDeploymentService implements DeploymentService {
  static const int _launcherControlPort = int.fromEnvironment(
    'NMTK_CONTROL_API_PORT',
    defaultValue: 8090,
  );

  ClientDeploymentService({
    AssetBundle? assets,
    http.Client? httpClient,
    DeploymentPersistenceFactory? persistenceFactory,
    KubernetesDeploymentService? kubernetes,
    SshDeploymentService ssh = const SshDeploymentService(),
    LocalDeploymentService local = const LocalDeploymentService(),
    RemoteServerProvisioner? provisioner,
    RemoteDeploymentRunner? runner,
    DeploymentHealthChecker? health,
  }) : _assets = assets ?? rootBundle,
       _kubernetes = kubernetes ?? const KubernetesDeploymentService(),
       _ssh = ssh,
       _local = local,
       _provisioner = provisioner ?? RemoteServerProvisioner(ssh: ssh),
       _runner = runner ?? RemoteDeploymentRunner(ssh: ssh),
       _health = health ?? DeploymentHealthChecker(httpClient: httpClient),
       _registry = JobRegistry(
         persistenceFactory: persistenceFactory ?? _defaultPersistence,
       );

  static Future<DeploymentPersistence> _defaultPersistence() async {
    return DeploymentPersistence(
      preferences: await SharedPreferences.getInstance(),
    );
  }

  final AssetBundle _assets;
  final KubernetesDeploymentService _kubernetes;
  final SshDeploymentService _ssh;
  final LocalDeploymentService _local;
  final RemoteServerProvisioner _provisioner;
  final RemoteDeploymentRunner _runner;
  final DeploymentHealthChecker _health;
  final JobRegistry _registry;

  @override
  Future<DeploymentSnapshot> load() async {
    final store = await _registry.store;
    final targets = await store.loadTargets();
    var activeJob = store.loadActiveJob();
    // A previous desktop version could persist a completed remote job after
    // only the server-local checks passed.  Recheck it from this device so a
    // stale success never boots the workspace into an endless loading state.
    final completedJob = activeJob;
    if (completedJob != null &&
        completedJob.stage == DeploymentPhase.completed.wireName) {
      final target = targets.where(
        (candidate) => candidate.id == completedJob.targetId,
      );
      if (target.length == 1 && target.first.targetType == 'remote_host') {
        try {
          activeJob = await _throughReachableEndpoints(
            target.first,
            (endpoints, adminToken) => _health.verifyRemoteApis(
              completedJob,
              target.first,
              attempts: 1,
              adminToken: adminToken,
              endpoints: endpoints,
              registry: _registry,
            ),
          );
        } catch (error) {
          activeJob = _health.clientReachabilityFailure(
            completedJob,
            target.first,
            cause: error,
          );
          await store.saveActiveJob(activeJob);
        }
      }
    }
    final interruptedAdministratorSetup =
        activeJob != null &&
        !activeJob.isTerminal &&
        !_registry.runningJobs.containsKey(activeJob.id) &&
        (!_registry.pendingTargets.containsKey(activeJob.id)) &&
        (activeJob.requiresEphemeralAdministrator ||
            !targets.any((target) => target.id == activeJob!.targetId) ||
            {
              DeploymentPhase.connecting.wireName,
              DeploymentPhase.preflight.wireName,
              DeploymentPhase.bootstrappingAccess.wireName,
              DeploymentPhase.reconcilingExistingInstall.wireName,
              DeploymentPhase.installingPrerequisites.wireName,
            }.contains(activeJob.stage));
    if (interruptedAdministratorSetup) {
      activeJob = activeJob.copyWith(
        stage: DeploymentPhase.failed.wireName,
        percent: 100,
        stageLabel: 'Remote setup was interrupted',
        error:
            'Setup stopped before its generated credential could be saved. '
            'Enter the administrator credential and run setup again.',
        terminalOutput: boundedTerminalOutput([
          ...activeJob.terminalOutput,
          '[client: administrator setup was interrupted when the app closed]',
        ]),
        requiresEphemeralAdministrator: false,
        failureDetails: const DeploymentFailureDetails(
          code: 'administrator_setup_interrupted',
          phase: 'bootstrapping_access',
          summary: 'Administrator setup was interrupted',
          recovery: 'Enter the administrator credential and run setup again.',
        ),
        clearActiveOperation: true,
        updatedAt: DateTime.now(),
      );
      await store.saveActiveJob(activeJob);
    }
    if (activeJob != null) _registry.jobs[activeJob.id] = activeJob;
    return DeploymentSnapshot(
      targets: targets,
      activeJob: activeJob,
      isReady:
          activeJob?.stage == DeploymentPhase.completed.wireName ||
          activeJob?.failureDetails?.existingConnectionReachable == true,
    );
  }

  @override
  Future<DeploymentPreflightResult> preflight(DeploymentRequest request) async {
    if (kIsWeb) {
      return _failedPreflight(
        'Direct deployment is available in the mobile and desktop apps.',
      );
    }
    if (request.targetType == 'local') {
      if (!_isDesktop) {
        return _failedPreflight(
          'This device cannot run backend containers. Choose a remote server '
          'or Kubernetes cluster.',
        );
      }
      if (request.mode == 'standalone') {
        return const DeploymentPreflightResult(
          status: 'ok',
          message: 'Local standalone prerequisites are available.',
          blockingFindings: [],
          degradedFindings: [],
          suggestedRecovery: 'No recovery action needed.',
        );
      }
      final engine = request.containerEngine;
      final result = await _local.run(engine, const ['--version']);
      if (result.exitCode != 0) {
        return _failedPreflight(
          '$engine is not installed on this machine. Install it and retry.',
        );
      }
      return const DeploymentPreflightResult(
        status: 'ok',
        message: 'Local container provider is ready.',
        blockingFindings: [],
        degradedFindings: [],
        suggestedRecovery: 'No recovery action needed.',
      );
    }
    if (request.targetType == 'kubernetes_cluster') {
      return _kubernetes.preflight(request);
    }
    if (request.host.trim().isEmpty || request.username.trim().isEmpty) {
      return _failedPreflight(
        'Enter the remote server address and SSH username.',
      );
    }
    SSHClient? client;
    try {
      client = await _ssh.connect(
        request: request,
        persistence: await _registry.store,
      );
      final sudoProbe = request.sshPassword.isNotEmpty
          ? 'printf %s\\\\n ${shellQuote(request.sshPassword)} | '
                'sudo -S -p "" true'
          : 'sudo -n true';
      final result = await client.runWithResult('''
printf 'os=%s\\n' "\$(uname -s 2>/dev/null || true)"
printf 'disk_kb=%s\\n' "\$(df -Pk "\$HOME" 2>/dev/null | awk 'NR==2 {print \$4}')"
printf 'curl=%s\\n' "\$(command -v curl >/dev/null 2>&1 && echo yes || echo no)"
printf 'engine=%s\\n' "\$(command -v ${shellQuote(request.containerEngine)} >/dev/null 2>&1 && echo yes || echo no)"
printf 'sudo=%s\\n' "\$($sudoProbe >/dev/null 2>&1 && echo yes || echo no)"
if command -v ss >/dev/null 2>&1; then
  printf 'ports=%s\\n' "\$(ss -ltn | awk 'NR>1 {print \$4}' | tr '\\n' ',')"
else
  printf 'ports=unknown\\n'
fi
''');
      if (result.exitCode != 0) {
        return _failedPreflight(
          'The server is reachable, but its prerequisites could not be read.',
        );
      }
      final fields = <String, String>{};
      for (final line in utf8.decode(result.stdout).split('\n')) {
        final separator = line.indexOf('=');
        if (separator > 0) {
          fields[line.substring(0, separator)] = line
              .substring(separator + 1)
              .trim();
        }
      }
      if (fields['os'] != 'Linux') {
        return _failedPreflight('Remote deployment requires a Linux server.');
      }
      final diskKb = int.tryParse(fields['disk_kb'] ?? '') ?? 0;
      if (diskKb < 5 * 1024 * 1024) {
        return _failedPreflight(
          'The server needs at least 5 GB of free disk space.',
        );
      }
      if (fields['curl'] != 'yes') {
        return _failedPreflight('Install curl on the server, then retry.');
      }
      if (fields['engine'] != 'yes' && fields['sudo'] != 'yes') {
        return _failedPreflight(
          '${request.containerEngine} is not installed and this SSH account '
          'cannot use sudo to install it.',
        );
      }
      final occupiedPorts = <int>[
        request.backendPort,
        _launcherControlPort,
        8008,
      ].where((port) => _portIsListed(fields['ports'], port)).toList();
      final degraded = <String>[
        if (fields['engine'] != 'yes')
          '${request.containerEngine} will be installed automatically.',
        if (occupiedPorts.isNotEmpty)
          'Ports ${occupiedPorts.join(', ')} are already in use; an existing '
              'NeuroToolkit stack will be upgraded in place.',
        if (fields['ports'] == 'unknown')
          'Port occupancy could not be checked because ss is unavailable.',
      ];
      return DeploymentPreflightResult(
        status: 'ok',
        message: 'SSH access and remote prerequisites are ready.',
        blockingFindings: const [],
        degradedFindings: degraded,
        suggestedRecovery: degraded.isEmpty
            ? 'No recovery action needed.'
            : 'Review the notes above, then continue.',
      );
    } catch (error) {
      return _failedPreflight(friendlySshError(error));
    } finally {
      client?.close();
    }
  }

  @override
  Future<RemoteUserBootstrapResult> bootstrapRemoteUser({
    required String host,
    required int sshPort,
    required String rootUsername,
    required String rootPassword,
    required String rootPrivateKey,
    required String containerEngine,
  }) {
    return _provisioner.bootstrapRemoteUser(
      host: host,
      sshPort: sshPort,
      rootUsername: rootUsername,
      rootPassword: rootPassword,
      rootPrivateKey: rootPrivateKey,
      containerEngine: containerEngine,
      registry: _registry,
    );
  }

  @override
  Future<DeploymentJob> setupRemoteServer(RemoteServerSetupRequest request) {
    return _provisioner.setupRemoteServer(
      request,
      registry: _registry,
      loadBundle: () => DeploymentAssetBundle.load(_assets),
      runDeployment: _runDeployment,
      isApiReady: (target) => _throughReachableEndpoints(
        target,
        (endpoints, adminToken) => _health.isApiReady(
          target,
          adminToken: adminToken,
          endpoints: endpoints,
        ),
      ),
    );
  }

  @override
  Future<DeploymentJob> deploy(DeploymentRequest request) =>
      _deploy(request, persistTargetImmediately: true);

  Future<DeploymentJob> _deploy(
    DeploymentRequest request, {
    required bool persistTargetImmediately,
  }) async {
    if (request.targetType == 'remote_host' && request.adminToken.isEmpty) {
      request = request.withAdminToken(_newAdminToken());
    }
    final bundle = await DeploymentAssetBundle.load(_assets);
    final targetId = request.targetType == 'remote_host'
        ? 'remote-${request.host.trim().replaceAll('.', '-')}'
        : _newId('target');
    final jobId = _newId('deploy');
    final target = DeploymentTarget.fromJson(
      request.toPublicJson(id: targetId)
        ..['updatedAt'] = DateTime.now().toIso8601String(),
    );
    final store = await _registry.store;
    if (persistTargetImmediately) {
      await store.saveTarget(target, request);
    } else {
      _registry.pendingTargets[jobId] = target;
      _registry.pendingRequests[jobId] = request;
    }
    final job = DeploymentJob(
      id: jobId,
      targetId: targetId,
      mode: request.mode,
      stage: DeploymentPhase.queued.wireName,
      percent: 0,
      stageLabel: 'Deployment queued',
      logs: const [],
      bundleVersion: bundle.version,
      bundleManifestHash: bundle.manifestHash,
      imageTag: request.deploymentImageTag,
      updatedAt: DateTime.now(),
    );
    _registry.jobs[jobId] = job;
    await store.saveActiveJob(job);
    _registry.runningJobs[jobId] = _runDeployment(job, target, request, bundle);
    unawaited(
      _registry.runningJobs[jobId]!.whenComplete(() {
        _registry.runningJobs.remove(jobId);
      }),
    );
    return job;
  }

  @override
  Future<DeploymentTarget> linkExistingTarget(DeploymentRequest request) async {
    final targetId = request.targetType == 'remote_host'
        ? 'remote-${request.host.trim().replaceAll('.', '-')}'
        : _newId('target');
    final store = await _registry.store;
    if (request.adminToken.isEmpty && request.targetType == 'remote_host') {
      // Ask the server first. A stored token is only a guess: an install that
      // failed after generating one leaves this app pinned to a token the
      // running backend never adopted, and reusing it makes every later
      // connection fail authentication with no way out but a reinstall. What
      // the live launcher control just accepted is authoritative.
      final recovered = await _runner.readExistingAdminToken(request, store);
      if (recovered.isNotEmpty) request = request.withAdminToken(recovered);
    }
    if (request.adminToken.isEmpty) {
      // Nothing readable on the server — a locked-down deployment account with
      // no usable sudo. Fall back to the stored token so relinking (e.g.
      // "Update credentials") does not wipe a token a prior deploy stored for
      // this same host and break an otherwise working tunnel.
      for (final existing in await store.loadTargets()) {
        if (existing.id != targetId) continue;
        final existingRequest = await store.requestForTarget(existing);
        if (existingRequest.adminToken.isNotEmpty) {
          request = request.withAdminToken(existingRequest.adminToken);
        }
        break;
      }
    }
    // Relinking supplies an operator credential for privileged recovery, not
    // a new owner for the backend. Overwriting the saved deployment account
    // with it pointed every later stack operation — repair, restart,
    // reinstall, the tunnel — at the operator's own home directory and
    // container store, which is empty, so `compose up` built a second stack
    // there and collided with the real one on its published ports.
    for (final existing in await store.loadTargets()) {
      if (existing.id != targetId) continue;
      final existingRequest = await store.requestForTarget(existing);
      if (existingRequest.username.trim().isNotEmpty &&
          existingRequest.sshPrivateKey.trim().isNotEmpty) {
        request = request.withDeploymentIdentity(
          username: existingRequest.username,
          sshPrivateKey: existingRequest.sshPrivateKey,
          authMethod: existing.authMode,
        );
      }
      break;
    }
    final target = DeploymentTarget.fromJson(
      request.toPublicJson(id: targetId)
        ..['updatedAt'] = DateTime.now().toIso8601String(),
    );
    await store.saveTarget(target, request);
    return target;
  }

  @override
  Future<DeploymentJob> fetchJob(String jobId) async {
    final job =
        _registry.jobs[jobId] ?? (await _registry.store).loadActiveJob();
    if (job == null || job.id != jobId) {
      throw StateError('Deployment job $jobId was not found on this device.');
    }
    if (job.isTerminal) {
      _registry.pendingTargets.remove(jobId);
      _registry.pendingRequests.remove(jobId);
      return job;
    }
    if (_registry.runningJobs.containsKey(jobId)) return job;

    final pendingTarget = _registry.pendingTargets[jobId];
    final pendingRequest = _registry.pendingRequests[jobId];
    final targets = await (await _registry.store).loadTargets();
    final savedTargets = targets.where(
      (candidate) => candidate.id == job.targetId,
    );
    final target =
        pendingTarget ?? (savedTargets.isEmpty ? null : savedTargets.first);
    if (target == null) return job;
    final request =
        pendingRequest ??
        await (await _registry.store).requestForTarget(target);
    if (target.targetType == 'remote_host') {
      return _runner.pollRemoteJob(
        job,
        target,
        request,
        registry: _registry,
        verifyRemoteApis: (j, t, {hostOverride}) => _throughReachableEndpoints(
          t,
          (endpoints, adminToken) => _health.verifyRemoteApis(
            j,
            t,
            hostOverride: hostOverride,
            adminToken: adminToken.isEmpty ? request.adminToken : adminToken,
            endpoints: endpoints,
            registry: _registry,
          ),
        ),
        clientReachabilityFailure: _health.clientReachabilityFailure,
      );
    }
    if (await _throughReachableEndpoints(
      target,
      (endpoints, adminToken) => _health.isApiReady(
        target,
        adminToken: adminToken,
        endpoints: endpoints,
      ),
    )) {
      return _registry.updateJob(
        job.copyWith(
          stage: DeploymentPhase.completed.wireName,
          percent: 100,
          stageLabel: 'Backend and launcher control are ready',
          updatedAt: DateTime.now(),
        ),
      );
    }
    return job;
  }

  @override
  Future<DeploymentJob> cancelJob(String jobId) async {
    final cancelledBootstrap = _provisioner.cancelAdministratorSession(jobId);
    final job = _registry.jobs[jobId] ?? await fetchJob(jobId);
    if (cancelledBootstrap) {
      _registry.pendingTargets.remove(jobId);
      _registry.pendingRequests.remove(jobId);
      return _registry.updateJob(
        job.copyWith(
          stage: DeploymentPhase.cancelled.wireName,
          stageLabel: 'Server setup cancelled',
          terminalOutput: boundedTerminalOutput([
            ...job.terminalOutput,
            '[client: administrator setup cancelled]',
          ]),
          requiresEphemeralAdministrator: false,
          updatedAt: DateTime.now(),
        ),
      );
    }
    final pendingTarget = _registry.pendingTargets[jobId];
    final pendingRequest = _registry.pendingRequests[jobId];
    final targets = await (await _registry.store).loadTargets();
    final matches = targets.where((target) => target.id == job.targetId);
    final target = pendingTarget ?? (matches.isEmpty ? null : matches.first);
    if (target != null && target.targetType == 'remote_host') {
      final request =
          pendingRequest ??
          await (await _registry.store).requestForTarget(target);
      final client = await _runner.connect(request, await _registry.store);
      try {
        final deployDir = await _runner.remoteDeployDir(client);
        await client.run(
          'test ! -f ${shellQuote('$deployDir/.jobs/$jobId.pid')} || '
          'kill "\$(cat ${shellQuote('$deployDir/.jobs/$jobId.pid')})" '
          '2>/dev/null || true',
        );
      } finally {
        client.close();
      }
    }
    _registry.pendingTargets.remove(jobId);
    _registry.pendingRequests.remove(jobId);
    return _registry.updateJob(
      job.copyWith(
        stage: DeploymentPhase.cancelled.wireName,
        stageLabel: 'Deployment cancelled',
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<DeploymentJob?> retryJob(String jobId) async {
    final job = await fetchJob(jobId);
    final targets = await (await _registry.store).loadTargets();
    final matches = targets.where((target) => target.id == job.targetId);
    if (matches.isEmpty) return null;
    return deploy(
      await (await _registry.store).requestForTarget(matches.first),
    );
  }

  @override
  Future<void> retryJupyter(String targetId) async {
    final targets = await (await _registry.store).loadTargets();
    final matches = targets.where((target) => target.id == targetId);
    if (matches.isEmpty) {
      throw StateError('Unknown deployment target.');
    }
    final target = matches.first;
    final request = await (await _registry.store).requestForTarget(target);
    final composeCommand =
        '${request.containerEngine} compose '
        '--project-name nmtk -f docker-compose.yml -f docker-compose.prod.yml'
        '${target.targetType == 'remote_host' ? ' -f docker-compose.remote.yml' : ''} '
        'up -d --no-deps jupyter-server';
    final host = target.host.isEmpty ? '127.0.0.1' : target.host;
    if (target.targetType == 'remote_host') {
      final client = await _runner.connect(request, await _registry.store);
      try {
        final deployDir = await _runner.remoteDeployDir(client);
        final elevated = request.containerEngine == 'docker'
            ? 'if command -v sg >/dev/null 2>&1; then '
                  'sg docker -c ${shellQuote(composeCommand)}; '
                  'else $composeCommand; fi'
            : composeCommand;
        await _runner.runChecked(
          client,
          'cd ${shellQuote(deployDir)} && $elevated',
          'Could not restart Jupyter.',
        );
      } finally {
        client.close();
      }
    } else {
      final directory = await _local.materializeAssets(_assets);
      await _local.runChecked(
        request.containerEngine,
        [
          'compose',
          '--project-name',
          'nmtk',
          '-f',
          'docker-compose.yml',
          '-f',
          'docker-compose.prod.yml',
          'up',
          '-d',
          '--no-deps',
          'jupyter-server',
        ],
        directory,
        launcherControlPort: _launcherControlPort,
      );
    }
    final ready = await _health.waitForHealth(
      Uri.parse('http://$host:8008/api/status'),
      attempts: 30,
      adminToken: request.adminToken,
    );
    if (!ready) {
      throw StateError('Jupyter still did not become ready after restart.');
    }
    final matchingJobs = _registry.jobs.values
        .where((j) => j.targetId == targetId)
        .toList();
    if (matchingJobs.isNotEmpty &&
        matchingJobs.first.error.startsWith('degraded optional capability')) {
      await _registry.updateJob(matchingJobs.first.copyWith(error: ''));
    }
  }

  /// Runs [body] against endpoints this device can actually reach.
  ///
  /// A remote backend publishes every port on the server's own loopback, so
  /// the only route to it from here is the same SSH tunnel the workspace
  /// uses. Probing `host:port` instead cannot connect at all, which used to
  /// report a healthy backend as unreachable and offer only a reinstall. The
  /// tunnel is private to this call so it can never disturb the workspace's.
  Future<T> _throughReachableEndpoints<T>(
    DeploymentTarget target,
    Future<T> Function(BackendEndpoints? endpoints, String adminToken) body,
  ) async {
    final store = await _registry.store;
    if (target.targetType != 'remote_host') {
      return body(null, (await store.requestForTarget(target)).adminToken);
    }
    BackendTunnelService? tunnel = BackendTunnelService();
    BackendEndpoints? endpoints;
    String adminToken;
    try {
      final session = await tunnel.open(target);
      endpoints = BackendEndpoints(
        suiteApi: session.suiteApiUri,
        launcherControl: session.launcherUri,
        jupyter: session.jupyterUri,
      );
      adminToken = session.adminToken;
    } on Object {
      // No tunnel available (no token yet, or SSH is refusing). Fall back to
      // host:port, which is all a legacy install that published on every
      // interface ever needed.
      await tunnel.close();
      tunnel = null;
      adminToken = (await store.requestForTarget(target)).adminToken;
    }
    try {
      return await body(endpoints, adminToken);
    } finally {
      await tunnel?.close();
    }
  }

  @override
  Future<SystemHealthReport> diagnoseTarget(String targetId) async {
    final targets = await (await _registry.store).loadTargets();
    final matches = targets.where((candidate) => candidate.id == targetId);
    if (matches.isEmpty) {
      return _health.diagnoseTarget(targetId, registry: _registry);
    }
    return _throughReachableEndpoints(
      matches.first,
      (endpoints, _) => _health.diagnoseTarget(
        targetId,
        registry: _registry,
        endpoints: endpoints,
      ),
    );
  }

  @override
  Future<SystemHealthReport> diagnoseHost(
    String host, {
    int backendPort = 9000,
  }) => _health.diagnoseHost(host, backendPort: backendPort);

  @override
  Future<SystemHealthReport> repairTarget(String targetId) async {
    final targets = await (await _registry.store).loadTargets();
    final matches = targets.where((candidate) => candidate.id == targetId);
    if (matches.isEmpty) {
      return _health.repairTarget(
        targetId,
        registry: _registry,
        assets: _assets,
        runner: _runner,
        local: _local,
      );
    }
    return _throughReachableEndpoints(
      matches.first,
      (endpoints, _) => _health.repairTarget(
        targetId,
        registry: _registry,
        assets: _assets,
        runner: _runner,
        local: _local,
        endpoints: endpoints,
      ),
    );
  }

  @override
  Future<DeploymentJob> reinstallTarget(
    String targetId, {
    bool factoryReset = false,
  }) async {
    final targets = await (await _registry.store).loadTargets();
    final matches = targets.where((target) => target.id == targetId);
    if (matches.isEmpty) throw StateError('Unknown deployment target.');
    final request = await (await _registry.store).requestForTarget(
      matches.first,
      cleanInstall: factoryReset,
    );
    return deploy(request);
  }

  @override
  Future<void> forgetHostKey({
    required String host,
    required int sshPort,
  }) async {
    await (await _registry.store).forgetHostKey(host: host, port: sshPort);
  }

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  Future<void> _runDeployment(
    DeploymentJob job,
    DeploymentTarget target,
    DeploymentRequest request,
    DeploymentAssetBundle bundle,
  ) async {
    try {
      if (request.targetType == 'remote_host') {
        await _runner.startRemoteDeployment(
          job,
          target,
          request,
          bundle,
          registry: _registry,
          assets: _assets,
        );
      } else if (request.targetType == 'kubernetes_cluster') {
        await _kubernetes.deployAndPersist(
          job,
          target,
          request,
          persistence: await _registry.store,
          emit: _registry.emit,
        );
      } else {
        await _local.deploy(
          job,
          request,
          assets: _assets,
          launcherControlPort: _launcherControlPort,
          emit: _registry.emit,
        );
        final verified = await _health.verifyRemoteApis(
          _registry.jobs[job.id] ?? job,
          target,
          hostOverride: '127.0.0.1',
          adminToken: request.adminToken,
          registry: _registry,
        );
        await _registry.updateJob(verified);
      }
    } catch (error) {
      final current = _registry.jobs[job.id] ?? job;
      final safeError = redactForLogging(error.toString(), request);
      final existingConnectionReachable = request.targetType == 'remote_host'
          ? await _throughReachableEndpoints(
              target,
              (endpoints, adminToken) => _health.isApiReady(
                target,
                adminToken: adminToken.isEmpty
                    ? request.adminToken
                    : adminToken,
                endpoints: endpoints,
              ),
            )
          : null;
      final failure = DeploymentFailureDetails(
        code: 'deployment_phase_failed',
        phase: current.stage,
        summary: _failureSummaryForPhase(current.stage),
        recovery: safeError.replaceFirst(
          RegExp(r'^(Bad state|Exception):\s*'),
          '',
        ),
        technicalDetails: boundedDiagnosticOutput(safeError),
        existingConnectionReachable: existingConnectionReachable,
      );
      await _registry.updateJob(
        current.copyWith(
          stage: DeploymentPhase.failed.wireName,
          percent: 100,
          stageLabel: failure.summary,
          error: failure.recovery,
          failureDetails: failure,
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  static String _failureSummaryForPhase(String phase) {
    return switch (phase) {
      'installing_prerequisites' =>
        'The selected container engine could not be prepared',
      'uploading_assets' => 'The deployment bundle could not be uploaded',
      'pulling_images' => 'The NMTK images could not be downloaded',
      'starting_containers' => 'The NMTK services could not be started',
      'verifying_suite_api' => 'The Suite API did not become reachable',
      'verifying_launcher_control' =>
        'Launcher control did not become reachable',
      _ => 'Server deployment failed',
    };
  }

  DeploymentPreflightResult _failedPreflight(String message) {
    return DeploymentPreflightResult(
      status: 'failed',
      message: 'preflight failed: $message',
      blockingFindings: ['preflight failed: $message'],
      degradedFindings: const [],
      suggestedRecovery: message,
    );
  }

  String _newAdminToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  static bool _portIsListed(String? listeners, int port) {
    if (listeners == null || listeners == 'unknown') return false;
    return RegExp('(?:^|[:,])$port(?:,|\$)').hasMatch(listeners);
  }
}
