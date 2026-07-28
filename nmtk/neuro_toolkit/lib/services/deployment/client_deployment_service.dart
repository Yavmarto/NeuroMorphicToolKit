import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/deployment_persistence.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/kubernetes_deployment.dart';
import 'package:neuro_toolkit/services/deployment/local_deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/ssh_deployment_service.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef DeploymentPersistenceFactory = Future<DeploymentPersistence> Function();

class DeploymentAssetBundle {
  const DeploymentAssetBundle({
    required this.version,
    required this.manifestHash,
    required this.fileHashes,
  });

  final int version;
  final String manifestHash;
  final Map<String, String> fileHashes;

  factory DeploymentAssetBundle.fromManifestBytes(Uint8List bytes) {
    final payload = jsonDecode(utf8.decode(bytes));
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Deployment manifest must be a JSON object.');
    }
    final version = payload['bundleVersion'];
    final files = payload['files'];
    if (version is! int || version <= 0 || files is! Map<String, dynamic>) {
      throw const FormatException(
          'Deployment manifest is missing bundle metadata.');
    }
    final fileHashes = <String, String>{
      for (final entry in files.entries)
        if (entry.value is String && (entry.value as String).isNotEmpty)
          entry.key: entry.value as String,
    };
    if (fileHashes.length != files.length) {
      throw const FormatException(
          'Deployment manifest contains an invalid file hash.');
    }
    return DeploymentAssetBundle(
      version: version,
      manifestHash: sha256.convert(bytes).toString(),
      fileHashes: Map.unmodifiable(fileHashes),
    );
  }

  static void validateRemoteChecksums({
    required DeploymentAssetBundle bundle,
    required Map<String, String> actualChecksums,
  }) {
    final expected = <String, String>{
      ...bundle.fileHashes,
      'deployment-manifest.json': bundle.manifestHash,
    };
    final mismatches = expected.entries
        .where((entry) => actualChecksums[entry.key] != entry.value)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (mismatches.isNotEmpty) {
      throw StateError(
        'Uploaded deployment bundle verification failed for '
        '${mismatches.join(', ')}.',
      );
    }
  }
}

class ClientDeploymentService implements DeploymentService {
  ClientDeploymentService({
    AssetBundle? assets,
    http.Client? httpClient,
    DeploymentPersistenceFactory? persistenceFactory,
    KubernetesDeploymentService? kubernetes,
    SshDeploymentService ssh = const SshDeploymentService(),
    LocalDeploymentService local = const LocalDeploymentService(),
  })  : _assets = assets ?? rootBundle,
        _httpClient = httpClient ?? http.Client(),
        _persistenceFactory = persistenceFactory ?? _defaultPersistence,
        _kubernetes = kubernetes ?? const KubernetesDeploymentService(),
        _ssh = ssh,
        _local = local;

  static Future<DeploymentPersistence> _defaultPersistence() async {
    return DeploymentPersistence(
      preferences: await SharedPreferences.getInstance(),
    );
  }

  static const _assetFiles = <String>[
    'deployment-manifest.json',
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
  static const _releaseImageTag = 'latest';

  final AssetBundle _assets;
  final http.Client _httpClient;
  final DeploymentPersistenceFactory _persistenceFactory;
  final KubernetesDeploymentService _kubernetes;
  final SshDeploymentService _ssh;
  final LocalDeploymentService _local;
  final Map<String, DeploymentJob> _jobs = {};
  final Map<String, Future<void>> _runningJobs = {};
  DeploymentPersistence? _persistence;

  Future<DeploymentPersistence> get _store async =>
      _persistence ??= await _persistenceFactory();

  @override
  Future<DeploymentSnapshot> load() async {
    final store = await _store;
    final targets = await store.loadTargets();
    final activeJob = store.loadActiveJob();
    if (activeJob != null) _jobs[activeJob.id] = activeJob;
    return DeploymentSnapshot(
      targets: targets,
      activeJob: activeJob,
      isReady: activeJob?.stage == DeploymentPhase.completed.wireName,
    );
  }

  @override
  Future<DeploymentPreflightResult> preflight(
    DeploymentRequest request,
  ) async {
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
      client = await _connect(request);
      final sudoProbe = request.sshPassword.isNotEmpty
          ? 'printf %s\\\\n ${_shellQuote(request.sshPassword)} | '
              'sudo -S -p "" true'
          : 'sudo -n true';
      final result = await client.runWithResult('''
printf 'os=%s\\n' "\$(uname -s 2>/dev/null || true)"
printf 'disk_kb=%s\\n' "\$(df -Pk "\$HOME" 2>/dev/null | awk 'NR==2 {print \$4}')"
printf 'curl=%s\\n' "\$(command -v curl >/dev/null 2>&1 && echo yes || echo no)"
printf 'engine=%s\\n' "\$(command -v ${_shellQuote(request.containerEngine)} >/dev/null 2>&1 && echo yes || echo no)"
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
          fields[line.substring(0, separator)] =
              line.substring(separator + 1).trim();
        }
      }
      if (fields['os'] != 'Linux') {
        return _failedPreflight(
          'Remote deployment requires a Linux server.',
        );
      }
      final diskKb = int.tryParse(fields['disk_kb'] ?? '') ?? 0;
      if (diskKb < 5 * 1024 * 1024) {
        return _failedPreflight(
          'The server needs at least 5 GB of free disk space.',
        );
      }
      if (fields['curl'] != 'yes') {
        return _failedPreflight(
          'Install curl on the server, then retry.',
        );
      }
      if (fields['engine'] != 'yes' && fields['sudo'] != 'yes') {
        return _failedPreflight(
          '${request.containerEngine} is not installed and this SSH account '
          'cannot use sudo to install it.',
        );
      }
      final occupiedPorts = <int>[
        request.backendPort,
        8090,
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
      return _failedPreflight(_friendlySshError(error));
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
    final client = await _connect(request);
    try {
      final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final temporaryKey = '/tmp/nmtk-deploy-$suffix';
      final script = '''
set -e
DEPLOY_USER=nmtk-deploy
id "\$DEPLOY_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "\$DEPLOY_USER"
ssh-keygen -q -t ed25519 -N "" -f ${_shellQuote(temporaryKey)}
install -d -m 700 -o "\$DEPLOY_USER" -g "\$DEPLOY_USER" "/home/\$DEPLOY_USER/.ssh"
cat ${_shellQuote('$temporaryKey.pub')} >>"/home/\$DEPLOY_USER/.ssh/authorized_keys"
chown "\$DEPLOY_USER:\$DEPLOY_USER" "/home/\$DEPLOY_USER/.ssh/authorized_keys"
chmod 600 "/home/\$DEPLOY_USER/.ssh/authorized_keys"
printf '%s ALL=(ALL) NOPASSWD:ALL\\n' "\$DEPLOY_USER" >"/etc/sudoers.d/nmtk-deploy"
chmod 440 "/etc/sudoers.d/nmtk-deploy"
cat ${_shellQuote(temporaryKey)}
rm -f ${_shellQuote(temporaryKey)} ${_shellQuote('$temporaryKey.pub')}
''';
      final elevated = rootUsername == 'root'
          ? 'sh -c ${_shellQuote(script)}'
          : rootPassword.isNotEmpty
              ? 'printf %s\\\\n ${_shellQuote(rootPassword)} | '
                  'sudo -S -p "" sh -c ${_shellQuote(script)}'
              : 'sudo -n sh -c ${_shellQuote(script)}';
      final result = await client.runWithResult(elevated);
      if (result.exitCode != 0) {
        throw StateError(
          'Could not create the deployment account: '
          '${utf8.decode(result.stderr).trim()}',
        );
      }
      return RemoteUserBootstrapResult(
        username: 'nmtk-deploy',
        sshPrivateKey: utf8.decode(result.stdout).trim(),
      );
    } finally {
      client.close();
    }
  }

  @override
  Future<DeploymentJob> deploy(DeploymentRequest request) async {
    final bundle = await _loadDeploymentBundle();
    final targetId = _newId('target');
    final jobId = _newId('deploy');
    final target = DeploymentTarget.fromJson(
      request.toPublicJson(id: targetId)
        ..['updatedAt'] = DateTime.now().toIso8601String(),
    );
    final store = await _store;
    await store.saveTarget(target, request);
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
      imageTag: _releaseImageTag,
      updatedAt: DateTime.now(),
    );
    _jobs[jobId] = job;
    await store.saveActiveJob(job);
    _runningJobs[jobId] = _runDeployment(job, target, request, bundle);
    unawaited(_runningJobs[jobId]!.whenComplete(() {
      _runningJobs.remove(jobId);
    }));
    return job;
  }

  @override
  Future<DeploymentJob> fetchJob(String jobId) async {
    final job = _jobs[jobId] ?? (await _store).loadActiveJob();
    if (job == null || job.id != jobId) {
      throw StateError('Deployment job $jobId was not found on this device.');
    }
    if (job.isTerminal || _runningJobs.containsKey(jobId)) return job;

    final targets = await (await _store).loadTargets();
    final target = targets.where((candidate) => candidate.id == job.targetId);
    if (target.isEmpty) return job;
    final request = await (await _store).requestForTarget(target.first);
    if (target.first.targetType == 'remote_host') {
      return _pollRemoteJob(job, target.first, request);
    }
    if (await _isApiReady(target.first)) {
      return _updateJob(
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
    final job = await fetchJob(jobId);
    final targets = await (await _store).loadTargets();
    final matches = targets.where((target) => target.id == job.targetId);
    if (matches.isNotEmpty && matches.first.targetType == 'remote_host') {
      final request = await (await _store).requestForTarget(matches.first);
      final client = await _connect(request);
      try {
        final deployDir = await _remoteDeployDir(client);
        await client.run(
          'test ! -f ${_shellQuote('$deployDir/.jobs/$jobId.pid')} || '
          'kill "\$(cat ${_shellQuote('$deployDir/.jobs/$jobId.pid')})" '
          '2>/dev/null || true',
        );
      } finally {
        client.close();
      }
    }
    return _updateJob(
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
    final targets = await (await _store).loadTargets();
    final matches = targets.where((target) => target.id == job.targetId);
    if (matches.isEmpty) return null;
    return deploy(await (await _store).requestForTarget(matches.first));
  }

  @override
  Future<void> retryJupyter(String targetId) async {
    final targets = await (await _store).loadTargets();
    final matches = targets.where((target) => target.id == targetId);
    if (matches.isEmpty) {
      throw StateError('Unknown deployment target.');
    }
    final target = matches.first;
    final request = await (await _store).requestForTarget(target);
    final composeCommand = '${request.containerEngine} compose '
        '--project-name nmtk -f docker-compose.yml -f docker-compose.prod.yml'
        '${target.targetType == 'remote_host' ? ' -f docker-compose.remote.yml' : ''} '
        'up -d --no-deps jupyter-server';
    final host = target.host.isEmpty ? '127.0.0.1' : target.host;
    if (target.targetType == 'remote_host') {
      final client = await _connect(request);
      try {
        final deployDir = await _remoteDeployDir(client);
        final elevated = request.containerEngine == 'docker'
            ? 'sg docker -c ${_shellQuote(composeCommand)}'
            : composeCommand;
        await _runChecked(
          client,
          'cd ${_shellQuote(deployDir)} && $elevated',
          'Could not restart Jupyter.',
        );
      } finally {
        client.close();
      }
    } else {
      final directory = await _materializeAssets();
      await _runLocalChecked(
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
      );
    }
    final ready = await _waitForHealth(
      Uri.parse('http://$host:8008/api/status'),
      attempts: 30,
    );
    if (!ready) {
      throw StateError('Jupyter still did not become ready after restart.');
    }
    final matchingJobs =
        _jobs.values.where((j) => j.targetId == targetId).toList();
    if (matchingJobs.isNotEmpty &&
        matchingJobs.first.error.startsWith('degraded optional capability')) {
      await _updateJob(matchingJobs.first.copyWith(error: ''));
    }
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
        await _startRemoteDeployment(job, target, request, bundle);
      } else if (request.targetType == 'kubernetes_cluster') {
        await _runKubernetesDeployment(job, target, request);
      } else {
        await _runLocalDeployment(job, target, request);
      }
    } catch (error) {
      await _updateJob(
        (_jobs[job.id] ?? job).copyWith(
          stage: DeploymentPhase.failed.wireName,
          percent: 100,
          stageLabel: 'Deployment failed',
          error: redactForLogging(error.toString(), request),
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _startRemoteDeployment(
    DeploymentJob job,
    DeploymentTarget target,
    DeploymentRequest request,
    DeploymentAssetBundle bundle,
  ) async {
    await _emit(job, DeploymentPhase.connecting, 5, 'Connecting with SSH');
    final client = await _connect(request);
    try {
      await _emit(
        job,
        DeploymentPhase.installingPrerequisites,
        12,
        'Preparing ${request.containerEngine}',
      );
      await _ensureRemoteEngine(client, request);
      final deployDir = await _remoteDeployDir(client);
      final jobDir = '$deployDir/.jobs';
      await _runChecked(
        client,
        'mkdir -p ${_shellQuote(deployDir)} ${_shellQuote(jobDir)}',
        'Could not create the deployment directory.',
      );
      await _emit(
        job,
        DeploymentPhase.uploadingAssets,
        25,
        'Uploading deployment bundle v${bundle.version} '
        '(${_shortHash(bundle.manifestHash)})',
      );
      await _uploadAssets(client, deployDir);
      await _verifyRemoteAssets(client, deployDir, bundle);
      await _emit(
        job,
        DeploymentPhase.uploadingAssets,
        30,
        'Verified deployment bundle v${bundle.version} '
        '(${_shortHash(bundle.manifestHash)})',
      );
      final status = '$jobDir/${job.id}.status';
      final log = '$jobDir/${job.id}.log';
      final pid = '$jobDir/${job.id}.pid';
      final installCommand = [
        'bash',
        'install.sh',
        request.containerEngine,
        request.backendPort.toString(),
        job.imageTag,
        request.cleanInstall.toString(),
        request.host,
        status,
        log,
      ].map(_shellQuote).join(' ');
      final detachedCommand = request.containerEngine == 'docker'
          ? 'sg docker -c ${_shellQuote(installCommand)}'
          : installCommand;
      final command = 'cd ${_shellQuote(deployDir)} && chmod 700 install.sh && '
          'nohup sh -c ${_shellQuote(detachedCommand)} </dev/null '
          '>/dev/null 2>&1 & echo \$! > ${_shellQuote(pid)}';
      await _runChecked(
        client,
        command,
        'Could not start the detached deployment job.',
      );
    } finally {
      client.close();
    }
  }

  Future<DeploymentJob> _pollRemoteJob(
    DeploymentJob job,
    DeploymentTarget target,
    DeploymentRequest request,
  ) async {
    final client = await _connect(request);
    try {
      final deployDir = await _remoteDeployDir(client);
      final jobDir = '$deployDir/.jobs';
      final result = await client.runWithResult(
        'cat ${_shellQuote('$jobDir/${job.id}.status')} 2>/dev/null; '
        'printf "\\n---NMTK-LOG---\\n"; '
        'tail -n 40 ${_shellQuote('$jobDir/${job.id}.log')} 2>/dev/null',
      );
      final output = utf8.decode(result.stdout);
      final sections = output.split('\n---NMTK-LOG---\n');
      final status = sections.first.trim().split('|');
      if (status.length < 3) return job;
      final stage = status[0];
      final logs = sections.length > 1
          ? sections[1]
              .split('\n')
              .where((line) => line.trim().isNotEmpty)
              .map((line) => redactForLogging(line, request))
              .toList(growable: false)
          : job.logs;
      var next = job.copyWith(
        stage: stage,
        percent: double.tryParse(status[1]) ?? job.percent,
        stageLabel: status.sublist(2).join('|'),
        logs: logs,
        error: stage == DeploymentPhase.failed.wireName
            ? (logs.isEmpty ? 'Remote deployment failed.' : logs.last)
            : '',
        updatedAt: DateTime.now(),
      );
      if (stage == DeploymentPhase.completed.wireName) {
        try {
          next = await _verifyRemoteApis(next, target);
        } catch (error) {
          // install.sh already confirmed readiness via loopback on the
          // deploy host itself -- don't let a client-side external-
          // reachability check block completion. Surface it as a warning;
          // the bootstrap probe that runs immediately after this (via
          // onDeploymentReady -> connectToDeploymentTarget ->
          // LauncherControlBootstrapService.ensureReady) does its own
          // authoritative, retrying check against the real host and will
          // report a proper error if it's genuinely unreachable.
          next = next.copyWith(
            stage: DeploymentPhase.completed.wireName,
            percent: 100,
            stageLabel: 'Backend and launcher control are ready',
            error: 'External verification warning: $error',
            updatedAt: DateTime.now(),
          );
        }
      }
      return _updateJob(next);
    } finally {
      client.close();
    }
  }

  Future<void> _runLocalDeployment(
    DeploymentJob job,
    DeploymentTarget target,
    DeploymentRequest request,
  ) async {
    if (request.mode == 'standalone') {
      await _emit(
        job,
        DeploymentPhase.completed,
        100,
        'Standalone backend target is configured',
      );
      return;
    }
    final directory = await _materializeAssets();
    final compose = <String>[
      'compose',
      '--project-name',
      'nmtk',
      '-f',
      'docker-compose.yml',
      '-f',
      'docker-compose.prod.yml',
    ];
    if (request.cleanInstall) {
      await _runLocalChecked(
        request.containerEngine,
        [...compose, 'down', '-v', '--remove-orphans'],
        directory,
        allowFailure: true,
      );
    }
    await _emit(job, DeploymentPhase.pullingImages, 45, 'Pulling images');
    await _runLocalChecked(
      request.containerEngine,
      [...compose, 'pull'],
      directory,
    );
    await _emit(
      job,
      DeploymentPhase.startingContainers,
      80,
      'Starting backend containers',
    );
    await _runLocalChecked(
      request.containerEngine,
      [...compose, 'up', '-d', '--no-build', '--remove-orphans'],
      directory,
    );
    final verified = await _verifyRemoteApis(
      _jobs[job.id] ?? job,
      target,
      hostOverride: '127.0.0.1',
    );
    await _updateJob(verified);
  }

  Future<void> _runKubernetesDeployment(
    DeploymentJob job,
    DeploymentTarget target,
    DeploymentRequest request,
  ) async {
    await _emit(
      job,
      DeploymentPhase.connecting,
      10,
      'Connecting to Kubernetes',
    );
    final host = await _kubernetes.deploy(
      request,
      onProgress: (phase, percent, message) =>
          _emit(job, phase, percent, message),
    );
    await (await _store).saveTarget(
      target.copyWith(
        host: host,
        lastReadiness: 'ready',
        updatedAt: DateTime.now(),
      ),
      request,
    );
    await _emit(
      job,
      DeploymentPhase.completed,
      100,
      'Kubernetes backend and launcher control are ready',
    );
  }

  Future<SSHClient> _connect(DeploymentRequest request) async {
    return _ssh.connect(
      request: request,
      persistence: await _store,
    );
  }

  Future<void> _ensureRemoteEngine(
    SSHClient client,
    DeploymentRequest request,
  ) async {
    final engine = request.containerEngine;
    final install = engine == 'podman'
        ? 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive '
            'apt-get install -y -qq podman podman-compose'
        : 'curl -fsSL https://get.docker.com | sh';
    final elevated = request.sshPassword.isNotEmpty
        ? 'printf %s\\\\n ${_shellQuote(request.sshPassword)} | '
            'sudo -S -p "" sh -c ${_shellQuote(install)}'
        : 'sudo -n sh -c ${_shellQuote(install)}';
    await _runChecked(
      client,
      'command -v ${_shellQuote(engine)} >/dev/null 2>&1 || $elevated',
      'Could not install $engine. Use an administrator account or configure '
          'passwordless sudo, then retry.',
    );
    if (engine == 'docker') {
      final addGroup = request.sshPassword.isNotEmpty
          ? 'printf %s\\\\n ${_shellQuote(request.sshPassword)} | '
              'sudo -S -p "" usermod -aG docker "\$USER"'
          : 'sudo -n usermod -aG docker "\$USER"';
      await _runChecked(
        client,
        'docker ps >/dev/null 2>&1 || $addGroup',
        'Docker is installed, but this SSH account cannot use it.',
      );
    }
  }

  Future<String> _remoteDeployDir(SSHClient client) async {
    final bytes = await client.run('printf %s "\$HOME"');
    final home = utf8.decode(bytes).trim();
    if (home.isEmpty) {
      throw StateError(
        'The SSH account has no home directory. Choose a normal login account.',
      );
    }
    return '$home/.nmtk/deploy';
  }

  Future<void> _uploadAssets(SSHClient client, String deployDir) async {
    final sftp = await client.sftp();
    for (final relative in _assetFiles) {
      final parent = path.posix.dirname(relative);
      if (parent != '.') {
        await client.run(
          'mkdir -p ${_shellQuote(path.posix.join(deployDir, parent))}',
        );
      }
      final data = await _assets.load('assets/deployment/$relative');
      final remote = await sftp.open(
        path.posix.join(deployDir, relative),
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.truncate |
            SftpFileOpenMode.write,
      );
      try {
        await remote.writeBytes(data.buffer.asUint8List());
      } finally {
        await remote.close();
      }
    }
  }

  Future<DeploymentAssetBundle> _loadDeploymentBundle() async {
    final data =
        await _assets.load('assets/deployment/deployment-manifest.json');
    return DeploymentAssetBundle.fromManifestBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  Future<void> _verifyRemoteAssets(
    SSHClient client,
    String deployDir,
    DeploymentAssetBundle bundle,
  ) async {
    final files = <String>[
      ...bundle.fileHashes.keys,
      'deployment-manifest.json',
    ];
    final result = await client.runWithResult(
      'cd ${_shellQuote(deployDir)} && sha256sum '
      '${files.map(_shellQuote).join(' ')}',
    );
    if (result.exitCode != 0) {
      throw StateError('Could not verify uploaded deployment assets.');
    }
    final checksums = <String, String>{};
    for (final line in utf8.decode(result.stdout).split('\n')) {
      final match = RegExp(r'^([a-fA-F0-9]{64})\\s+\\*?(.+)$').firstMatch(line);
      if (match != null) {
        checksums[match.group(2)!] = match.group(1)!.toLowerCase();
      }
    }
    DeploymentAssetBundle.validateRemoteChecksums(
      bundle: bundle,
      actualChecksums: checksums,
    );
  }

  static String _shortHash(String hash) =>
      hash.length <= 12 ? hash : hash.substring(0, 12);

  Future<Directory> _materializeAssets() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(path.join(support.path, 'deployment'));
    await directory.create(recursive: true);
    for (final relative in _assetFiles) {
      final file = File(path.join(directory.path, relative));
      await file.parent.create(recursive: true);
      final data = await _assets.load('assets/deployment/$relative');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    return directory;
  }

  Future<DeploymentJob> _verifyRemoteApis(
    DeploymentJob job,
    DeploymentTarget target, {
    String? hostOverride,
  }) async {
    final host = hostOverride ?? target.host;
    final suiteReady = await _waitForHealth(
      Uri.parse('http://$host:${target.backendPort}/api/suite/health'),
    );
    if (!suiteReady) {
      throw StateError(
        'Suite API did not become ready at $host:${target.backendPort}.',
      );
    }
    final launcherReady = await _waitForHealth(
      Uri.parse('http://$host:8090/health'),
    );
    if (!launcherReady) {
      throw StateError(
        'Launcher control did not become ready at $host:8090.',
      );
    }
    final jupyterReady = await _waitForHealth(
      Uri.parse('http://$host:8008/api/status'),
      attempts: 2,
    );
    final logs = [...job.logs];
    if (!jupyterReady) {
      logs.add(
        'degraded optional capability: Jupyter is not ready; core services '
        'are available.',
      );
    }
    final optionalCapabilityError = jupyterReady
        ? ''
        : 'degraded optional capability: Jupyter is not ready; core services '
            'are available.';
    return job.copyWith(
      stage: DeploymentPhase.completed.wireName,
      percent: 100,
      stageLabel: 'Backend and launcher control are ready',
      logs: logs,
      error: optionalCapabilityError,
      updatedAt: DateTime.now(),
    );
  }

  Future<bool> _isApiReady(DeploymentTarget target) async {
    final host = target.host.isEmpty ? '127.0.0.1' : target.host;
    return _waitForHealth(
      Uri.parse('http://$host:8090/health'),
      attempts: 1,
    );
  }

  Future<bool> _waitForHealth(Uri uri, {int attempts = 60}) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final response =
            await _httpClient.get(uri).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) return true;
      } catch (_) {
        // Startup connection failures are expected while containers warm.
      }
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    return false;
  }

  Future<void> _runChecked(
    SSHClient client,
    String command,
    String failureMessage,
  ) async {
    final result = await client.runWithResult(command);
    if (result.exitCode == 0) return;
    final details = utf8.decode(result.stderr).trim();
    throw StateError(
      details.isEmpty ? failureMessage : '$failureMessage $details',
    );
  }

  Future<void> _runLocalChecked(
    String executable,
    List<String> arguments,
    Directory directory, {
    bool allowFailure = false,
  }) async {
    final result = await _local.run(
      executable,
      arguments,
      workingDirectory: directory.path,
      environment: {
        ...Platform.environment,
        'SUITE_API_PORT': '9000',
        'LAUNCHER_CONTROL_PORT': '8090',
        'NMTK_IMAGE_TAG': 'latest',
      },
    );
    if (result.exitCode != 0 && !allowFailure) {
      throw StateError(
        '$executable ${arguments.join(' ')} failed: '
        '${result.stderr.toString().trim()}',
      );
    }
  }

  Future<void> _emit(
    DeploymentJob original,
    DeploymentPhase phase,
    double percent,
    String label,
  ) async {
    final current = _jobs[original.id] ?? original;
    await _updateJob(
      current.copyWith(
        stage: phase.wireName,
        percent: percent,
        stageLabel: label,
        logs: [...current.logs, label],
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<DeploymentJob> _updateJob(DeploymentJob job) async {
    _jobs[job.id] = job;
    await (await _store).saveActiveJob(job);
    return job;
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

  static String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  static bool _portIsListed(String? listeners, int port) {
    if (listeners == null || listeners == 'unknown') return false;
    return RegExp('(?:^|[:,])$port(?:,|\$)').hasMatch(listeners);
  }

  static String _friendlySshError(Object error) {
    final message = error.toString();
    if (message.toLowerCase().contains('host key')) {
      return 'The SSH host key changed. Confirm the server identity before '
          'trying again.';
    }
    if (message.toLowerCase().contains('auth')) {
      return 'SSH authentication failed. Check the username and credentials.';
    }
    return 'Could not connect over SSH: $message';
  }

  @visibleForTesting
  static String redactForLogging(
    String value,
    DeploymentRequest request,
  ) {
    var result = value;
    for (final secret in [
      request.sshPassword,
      request.sshPrivateKey,
      request.kubeconfig,
    ]) {
      if (secret.isNotEmpty) result = result.replaceAll(secret, '[redacted]');
    }
    return result;
  }

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";
}
