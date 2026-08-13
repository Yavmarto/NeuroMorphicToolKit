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

class _DeploymentBundleIntegrityException implements Exception {
  const _DeploymentBundleIntegrityException(this.files);

  final List<String> files;
}

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

  /// Parses the standard output format emitted by GNU and BusyBox sha256sum.
  ///
  /// This is deliberately separate from validation so a malformed command
  /// response is reported as an operator-facing transport failure rather than
  /// as though every uploaded file had changed.
  static Map<String, String> parseRemoteChecksumOutput(String output) {
    final checksums = <String, String>{};
    for (final line in output.split('\n')) {
      final match = RegExp(r'^([a-fA-F0-9]{64})\s+\*?(.+)$').firstMatch(line);
      if (match != null) {
        checksums[match.group(2)!] = match.group(1)!.toLowerCase();
      }
    }
    if (checksums.isEmpty) {
      throw const FormatException(
        'Remote checksum verification returned unreadable output.',
      );
    }
    return Map.unmodifiable(checksums);
  }
}

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
    'nmtk-stack.sh',
    'monitoring/alertmanager/alertmanager.yml',
    'monitoring/loki/loki-config.yml',
    'monitoring/prometheus/alert_rules.yml',
    'monitoring/prometheus/prometheus.yml',
    'monitoring/promtail/promtail-config.yml',
  ];
  static const _releaseImageTag = 'latest';
  static const _bundleIntegrityRecovery =
      'This app build contains an inconsistent deployment bundle. '
      'Update or reinstall NMTK, then retry setup. The server was not changed.';

  /// How long the administrator session may stay silent while no single server
  /// command is nominally running. Long enough to cover the gaps between steps,
  /// short enough that a wedged bootstrap surfaces while the user is still
  /// watching.
  static const _bootstrapIdleTimeoutSeconds = 90;

  /// Grace period for the transcript streams to reach EOF once the script has
  /// reported its own exit. See [_drainTranscriptStreams].
  static const _administratorDrainTimeout = Duration(seconds: 3);

  /// Grace period for queued progress persistence once the session is over.
  static const _streamedUpdateSettleTimeout = Duration(seconds: 10);

  /// Upper bound on one status-file read. Without it a wedged SSH read stops
  /// every later poll, because the notifier drops overlapping ticks.
  static const _statusPollTimeout = Duration(seconds: 20);

  final AssetBundle _assets;
  final http.Client _httpClient;
  final DeploymentPersistenceFactory _persistenceFactory;
  final KubernetesDeploymentService _kubernetes;
  final SshDeploymentService _ssh;
  final LocalDeploymentService _local;
  final Map<String, DeploymentJob> _jobs = {};
  final Map<String, Future<void>> _runningJobs = {};
  final Map<String, DeploymentTarget> _pendingTargets = {};
  final Map<String, DeploymentRequest> _pendingRequests = {};
  final Map<String, _AdministratorOperation> _administratorOperations = {};
  final Map<String, Timer> _operationHeartbeatTimers = {};
  final Map<String, Timer> _terminalPersistenceTimers = {};
  DeploymentPersistence? _persistence;

  Future<DeploymentPersistence> get _store async =>
      _persistence ??= await _persistenceFactory();

  @override
  Future<DeploymentSnapshot> load() async {
    final store = await _store;
    final targets = await store.loadTargets();
    var activeJob = store.loadActiveJob();
    // A previous desktop version could persist a completed remote job after
    // only the server-local checks passed.  Recheck it from this device so a
    // stale success never boots the workspace into an endless loading state.
    final completedJob = activeJob;
    if (completedJob != null &&
        completedJob.stage == DeploymentPhase.completed.wireName) {
      final target =
          targets.where((candidate) => candidate.id == completedJob.targetId);
      if (target.length == 1 && target.first.targetType == 'remote_host') {
        try {
          activeJob = await _verifyRemoteApis(
            completedJob,
            target.first,
            attempts: 1,
          );
        } catch (_) {
          activeJob = _clientReachabilityFailure(completedJob, target.first);
          await store.saveActiveJob(activeJob);
        }
      }
    }
    final interruptedAdministratorSetup = activeJob != null &&
        !activeJob.isTerminal &&
        !_runningJobs.containsKey(activeJob.id) &&
        (!_pendingTargets.containsKey(activeJob.id)) &&
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
        error: 'Setup stopped before its generated credential could be saved. '
            'Enter the administrator credential and run setup again.',
        terminalOutput: _boundedTerminalOutput([
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
    if (activeJob != null) _jobs[activeJob.id] = activeJob;
    return DeploymentSnapshot(
      targets: targets,
      activeJob: activeJob,
      isReady: activeJob?.stage == DeploymentPhase.completed.wireName ||
          activeJob?.failureDetails?.existingConnectionReachable == true,
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
    return _bootstrapRemoteUser(
      host: host,
      sshPort: sshPort,
      rootUsername: rootUsername,
      rootPassword: rootPassword,
      rootPrivateKey: rootPrivateKey,
      containerEngine: containerEngine,
      reinstallMode: RemoteReinstallMode.preserveData,
      jobId: _newId('bootstrap'),
    );
  }

  @override
  Future<DeploymentJob> setupRemoteServer(
    RemoteServerSetupRequest request,
  ) async {
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
      throw const FormatException(
        'Remote setup supports Docker or Podman.',
      );
    }

    final bundle = await _loadDeploymentBundle();
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
    _jobs[jobId] = job;
    _pendingTargets[jobId] = target;
    await (await _store).saveActiveJob(job);
    _runningJobs[jobId] = _runRemoteSetup(
      job,
      target,
      request,
      bundle,
    );
    unawaited(_runningJobs[jobId]!.whenComplete(() {
      _runningJobs.remove(jobId);
    }));
    return job;
  }

  Future<void> _runRemoteSetup(
    DeploymentJob job,
    DeploymentTarget target,
    RemoteServerSetupRequest setupRequest,
    DeploymentAssetBundle bundle,
  ) async {
    final host = target.host;
    try {
      await _emit(
        job,
        DeploymentPhase.connecting,
        2,
        'Connecting with administrator access',
      );
      await _emit(
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
        onPhase: (phase, percent, label) => _emit(
          job,
          phase,
          percent,
          label,
        ),
        onOperation: (operation) => _setActiveOperation(job.id, operation),
        onTerminalOutput: (line) => _appendTerminalOutput(job.id, line),
        jobId: job.id,
      );
      final afterBootstrap = _jobs[job.id] ?? job;
      if (afterBootstrap.stage == DeploymentPhase.cancelled.wireName) return;
      final handoffJob = afterBootstrap.copyWith(
        stage: DeploymentPhase.connecting.wireName,
        percent: 18,
        stageLabel: 'Connecting with deployment account',
        logs: [
          ...afterBootstrap.logs,
          'Connecting with deployment account',
        ],
        requiresEphemeralAdministrator: false,
        clearActiveOperation: true,
        updatedAt: DateTime.now(),
      );
      await _updateJob(handoffJob);
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
      _pendingTargets[job.id] = target;
      _pendingRequests[job.id] = deploymentRequest;
      await _runDeployment(handoffJob, target, deploymentRequest, bundle);
    } catch (error) {
      final current = _jobs[job.id] ?? job;
      if (current.stage == DeploymentPhase.cancelled.wireName) return;
      final failure = await _remoteSetupFailureDetails(
        error,
        target,
        setupRequest,
        current.stage,
      );
      await _updateJob(
        current.copyWith(
          stage: DeploymentPhase.failed.wireName,
          percent: 100,
          stageLabel: failure.summary,
          logs: [...current.logs, failure.summary],
          error: failure.recovery,
          failureDetails: failure,
          terminalOutput: _boundedTerminalOutput([
            ...current.terminalOutput,
            if (current.terminalOutput.isEmpty ||
                !current.terminalOutput.last.startsWith('[client:'))
              '[client: ${failure.summary}]',
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
    String currentPhase,
  ) async {
    final existingConnectionReachable = await _isApiReady(target);
    if (error is _RemoteSetupException) {
      return error.details.copyWithConnection(existingConnectionReachable);
    }
    final requestForRedaction = DeploymentRequest(
      targetType: 'remote_host',
      mode: 'docker',
      displayName: target.displayName,
      host: target.host,
      username: request.adminUsername,
      sshPort: request.sshPort,
      authMethod:
          request.adminPrivateKey.isNotEmpty ? 'ssh_key' : 'ssh_password',
      sshPassword: request.adminPassword,
      sshPrivateKey: request.adminPrivateKey,
      containerEngine: request.containerEngine,
    );
    final detail = _boundedDiagnosticOutput(
      redactForLogging(error.toString(), requestForRedaction),
    );
    final friendly = redactForLogging(
      _friendlySshError(error),
      requestForRedaction,
    );
    final isAuthentication =
        friendly.toLowerCase().contains('authentication failed');
    return DeploymentFailureDetails(
      code: isAuthentication ? 'admin_authentication_failed' : 'ssh_failed',
      phase: currentPhase,
      summary: isAuthentication
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
    Future<void> Function(
      DeploymentPhase phase,
      double percent,
      String label,
    )? onPhase,
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
    final client = await _connect(request);
    try {
      final result = await _runAdministratorScript(
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
        throw _RemoteSetupException(
          _bootstrapFailureDetails(
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

  static DeploymentFailureDetails _bootstrapFailureDetails(
    String stderr, {
    required int exitCode,
    required String rootPassword,
    required String rootPrivateKey,
  }) {
    final sanitized = _boundedDiagnosticOutput(
      _redactBootstrapOutput(stderr, rootPassword, rootPrivateKey),
    );
    final marker = RegExp(
      r'NMTK_SETUP_ERROR\|([^|]+)\|([^|]+)\|(\d+)\|([^\r\n]+)',
    ).allMatches(stderr).lastOrNull;
    final code = marker?.group(1) ?? _legacyBootstrapCode(stderr);
    final phase = marker?.group(2) ?? _phaseForFailureCode(code);
    final details = _failureCopyForCode(code);
    // When the server names the account it stumbled on, that sentence is the
    // only place the name appears — the code's stock copy cannot know it, and
    // the ✓/✗ lines that used to carry it never reach the transcript. The
    // generic "… failed or timed out." wording adds nothing, so skip it.
    final serverMessage = marker?.group(4)?.trim() ?? '';
    final recovery = serverMessage.contains(' user ') &&
            !serverMessage.endsWith('failed or timed out.')
        ? '$serverMessage ${details.$2}'
        : details.$2;
    return DeploymentFailureDetails(
      code: code,
      phase: phase,
      summary: details.$1,
      recovery: recovery,
      technicalDetails: sanitized,
      exitCode: int.tryParse(marker?.group(3) ?? '') ?? exitCode,
    );
  }

  @visibleForTesting
  static DeploymentFailureDetails parseBootstrapFailureForTesting(
    String stderr, {
    required int exitCode,
    String rootPassword = '',
    String rootPrivateKey = '',
  }) {
    return _bootstrapFailureDetails(
      stderr,
      exitCode: exitCode,
      rootPassword: rootPassword,
      rootPrivateKey: rootPrivateKey,
    );
  }

  static String _legacyBootstrapCode(String stderr) {
    final lower = stderr.toLowerCase();
    if (lower.contains('sudo') &&
        (lower.contains('password') ||
            lower.contains('authentication') ||
            lower.contains('privileged'))) {
      return 'sudo_access_denied';
    }
    if (lower.contains('unsupported operating system')) {
      return 'unsupported_os';
    }
    if (lower.contains('disk space')) return 'insufficient_disk';
    if (lower.contains('installed but inaccessible')) {
      return lower.contains('podman')
          ? 'podman_inspection_failed'
          : 'docker_inspection_failed';
    }
    if (lower.contains('cleanup failed')) return 'container_cleanup_failed';
    return 'unknown_bootstrap_failure';
  }

  static String _phaseForFailureCode(String code) {
    if (code.contains('cleanup') || code.contains('inspection')) {
      return DeploymentPhase.reconcilingExistingInstall.wireName;
    }
    if (code.contains('install') || code == 'unsupported_os') {
      return DeploymentPhase.installingPrerequisites.wireName;
    }
    if (code == 'insufficient_disk') {
      return DeploymentPhase.preflight.wireName;
    }
    return DeploymentPhase.bootstrappingAccess.wireName;
  }

  static (String, String) _failureCopyForCode(String code) {
    return switch (code) {
      'sudo_access_denied' => (
          'Administrator privileges could not be confirmed',
          'Use an account that can run sudo, check its password, then retry.',
        ),
      'unsupported_os' => (
          'This server operating system is not supported',
          'Remote setup requires a Debian or Ubuntu Linux server.',
        ),
      'insufficient_disk' => (
          'The server does not have enough free disk space',
          'Free at least 5 GB on the server, then retry.',
        ),
      'docker_inspection_failed' => (
          'Docker installations could not be inspected',
          'Ensure Docker is running and the administrator can access it, then retry.',
        ),
      'podman_inspection_failed' => (
          'Podman installations could not be inspected',
          'Administrator access succeeded, but the server’s own Podman '
              'installation did not answer. Restart the server, then retry. '
              'Podman belonging to other accounts on the server is skipped '
              'automatically and never blocks setup.',
        ),
      'container_cleanup_failed' => (
          'Existing NMTK containers could not be removed safely',
          'Review the administrator details, correct the reported container permission, then retry.',
        ),
      'volume_cleanup_failed' => (
          'NMTK server data could not be erased safely',
          'Review the volume permission shown in the details before retrying Factory Reset.',
        ),
      'engine_install_failed' => (
          'The selected container engine could not be installed',
          'Check package-manager and network access on the server, then retry.',
        ),
      'deploy_account_failed' => (
          'The deployment account could not be prepared',
          'The app could not repair the server’s deployment account '
              'automatically. Restart the server, then select Retry setup.',
        ),
      'podman_api_start_failed' => (
          'The Podman service could not be started',
          'The app tried both supported Podman startup methods automatically. '
              'Restart the server, then select Set up and connect again.',
        ),
      _ => (
          'The server preparation command failed',
          'Open the administrator details below, correct the reported server error, then retry.',
        ),
    };
  }

  static String _redactBootstrapOutput(
    String value,
    String rootPassword,
    String rootPrivateKey,
  ) {
    var result = value;
    for (final secret in [rootPassword, rootPrivateKey]) {
      if (secret.isNotEmpty) result = result.replaceAll(secret, '[redacted]');
    }
    result = result.replaceAll(
      RegExp(r'NMTK_DEPLOY_PRIVATE_KEY_B64=[A-Za-z0-9+/=]+'),
      'NMTK_DEPLOY_PRIVATE_KEY_B64=[redacted]',
    );
    result = result.replaceAll(
      RegExp(
        r'-----BEGIN OPENSSH PRIVATE KEY-----[\s\S]*?-----END OPENSSH PRIVATE KEY-----',
      ),
      '[redacted private key]',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'\b(password|token|api[_-]?key|secret)=([^\s]+)',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=[redacted]',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'\b(NMTK_[A-Z0-9_]*(?:PASSWORD|TOKEN|PRIVATE_KEY|SECRET))=([^\s]+)',
      ),
      (match) => '${match.group(1)}=[redacted]',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'(authorization:\s*(?:bearer|basic)\s+)([^\s]+)',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}[redacted]',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'([a-z][a-z0-9+.-]*://)([^/\s:@]+):([^@\s/]+)@',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}[redacted]@',
    );
    result = result
        .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    return result;
  }

  static String _boundedDiagnosticOutput(String value) {
    const maxCharacters = 8000;
    final normalized = value.trim();
    if (normalized.length <= maxCharacters) return normalized;
    return '… output truncated …\n'
        '${normalized.substring(normalized.length - maxCharacters)}';
  }

  static String buildRemoteBootstrapScript({
    required String containerEngine,
    required bool factoryReset,
  }) {
    final resetFlag = factoryReset ? 'true' : 'false';
    return r'''
set -euo pipefail
# Every privilege drop below (runuser/env, and any added later) inherits this
# shell's working directory, and runuser does not change it. The SSH login lands
# in the administrator's home, which other accounts cannot traverse on modern
# distributions, so a dropped-privilege child fails before it can even start.
# "/" is traversable by every account. Nothing in this script uses a relative
# path, so moving here is safe.
cd /
ENGINE="__ENGINE__"
FACTORY_RESET="__FACTORY_RESET__"
DEPLOY_USER="nmtk-deploy"
DEPLOY_GROUP="$DEPLOY_USER"
PROJECTS="nmtk nmtk-deploy deploy"
CURRENT_PHASE="preflight_running"
RUNTIME_BASE="${NMTK_SETUP_RUNTIME_BASE:-/run/user}"
TEMP_RUNTIME_DIRS=()
TEMP_COMMAND_DIRS=()
TEMPORARY_KEY_DIR=""

phase() {
  CURRENT_PHASE="$1"
  printf 'NMTK_SETUP_PHASE|%s|%s|%s\n' "$1" "$2" "$3"
}
fail() {
  code="$1"
  exit_code="$2"
  message="$3"
  trap - ERR
  printf 'NMTK_SETUP_ERROR|%s|%s|%s|%s\n' \
    "$code" "$CURRENT_PHASE" "$exit_code" "$message" >&2
  exit "$exit_code"
}
trap 'exit_code=$?; printf "NMTK_SETUP_ERROR|unexpected_setup_failure|%s|%s|A server command failed unexpectedly.\\n" "$CURRENT_PHASE" "$exit_code" >&2' ERR

terminal() {
  printf 'NMTK_SETUP_TERMINAL|%s\n' "$1"
}
command_marker() {
  printf 'NMTK_SETUP_COMMAND|%s\n' "$1"
}
command_exit_marker() {
  printf 'NMTK_SETUP_COMMAND_EXIT|%s|%s\n' "$1" "$2"
}
step_marker() {
  printf 'NMTK_SETUP_STEP|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4"
}
# Announces that the script itself is finished. The client treats this as the
# authoritative end of the administrator session: rootless Podman leaves
# lingering processes that inherit this SSH channel, so waiting for channel EOF
# would hang forever even though setup succeeded.
done_marker() {
  printf 'NMTK_SETUP_DONE|%s\n' "$1"
}
cleanup_temporary_setup_files() {
  exit_code="$?"
  trap - EXIT
  cleanup_failed=0
  key_cleanup_failed=0
  cleanup_user=""
  for runtime_entry in "${TEMP_RUNTIME_DIRS[@]-}"; do
    [ -n "$runtime_entry" ] || continue
    runtime_user="${runtime_entry%%:*}"
    runtime_dir="${runtime_entry#*:}"
    [ -n "$runtime_dir" ] || continue
    case "$runtime_dir" in
      /tmp/nmtk-podman-runtime.*)
        set +e
        timeout --signal=TERM --kill-after=5s 30s \
          rm -rf -- "$runtime_dir"
        cleanup_exit="$?"
        set -e
        if [ "$cleanup_exit" -ne 0 ]; then
          cleanup_failed=1
          cleanup_user="$runtime_user"
          terminal "✗ Temporary Podman runtime cleanup failed for user $runtime_user"
        fi
        ;;
      esac
  done
  if [ -n "$TEMPORARY_KEY_DIR" ]; then
    case "$TEMPORARY_KEY_DIR" in
      /tmp/nmtk-deploy-key.*)
        set +e
        timeout --signal=TERM --kill-after=5s 30s \
          rm -rf -- "$TEMPORARY_KEY_DIR"
        key_cleanup_exit="$?"
        set -e
        if [ "$key_cleanup_exit" -ne 0 ]; then
          cleanup_failed=1
          key_cleanup_failed=1
          terminal "✗ Temporary deployment credential cleanup failed"
        fi
        ;;
      esac
  fi
  for command_dir in "${TEMP_COMMAND_DIRS[@]-}"; do
    case "$command_dir" in
      /tmp/nmtk-command-output.*)
        rm -rf -- "$command_dir" 2>/dev/null || true
        ;;
    esac
  done
  if [ "$cleanup_failed" -eq 1 ] && [ "$exit_code" -eq 0 ]; then
    if [ "$key_cleanup_failed" -eq 1 ]; then
      printf 'NMTK_SETUP_ERROR|deploy_account_failed|%s|26|%s\n' \
        "$CURRENT_PHASE" \
        "The temporary deployment credential directory could not be removed." >&2
      done_marker 26
      exit 26
    else
      printf 'NMTK_SETUP_ERROR|podman_inspection_failed|%s|29|%s\n' \
        "$CURRENT_PHASE" \
        "Administrator access succeeded, but the temporary Podman runtime for user $cleanup_user could not be removed." >&2
      done_marker 29
      exit 29
    fi
  fi
  done_marker "$exit_code"
  exit "$exit_code"
}
trap cleanup_temporary_setup_files EXIT
STEP_OUTPUT=""
STEP_ERROR=""
STEP_EXIT=0
# Set to 1 only while inspecting a third-party account's rootless Podman.
RUNTIME_SWEEP_OPTIONAL=0
SKIPPED_PODMAN_ACCOUNTS=""
terminate_residual_command_group() {
  local group_pid="$1"
  kill -TERM -- "-$group_pid" 2>/dev/null || return 0
  for _ in {1..20}; do
    kill -0 -- "-$group_pid" 2>/dev/null || return 0
    sleep 0.05
  done
  kill -KILL -- "-$group_pid" 2>/dev/null || true
}

drain_capture_streams() {
  local stdout_pid="$1"
  local stderr_pid="$2"
  local stdout_forced=0
  local stderr_forced=0
  local stdout_alive=0
  local stderr_alive=0

  for _ in {1..40}; do
    stdout_alive=0
    stderr_alive=0
    kill -0 "$stdout_pid" 2>/dev/null && stdout_alive=1
    kill -0 "$stderr_pid" 2>/dev/null && stderr_alive=1
    [ "$stdout_alive" -eq 0 ] && [ "$stderr_alive" -eq 0 ] && break
    sleep 0.05
  done
  if kill -0 "$stdout_pid" 2>/dev/null; then
    stdout_forced=1
    kill -TERM "$stdout_pid" 2>/dev/null || true
  fi
  if kill -0 "$stderr_pid" 2>/dev/null; then
    stderr_forced=1
    kill -TERM "$stderr_pid" 2>/dev/null || true
  fi

  wait "$stdout_pid"
  stdout_tee_exit="$?"
  wait "$stderr_pid"
  stderr_tee_exit="$?"
  [ "$stdout_forced" -eq 0 ] || stdout_tee_exit=0
  [ "$stderr_forced" -eq 0 ] || stderr_tee_exit=0
}

# Runs one step and records its exit code in STEP_EXIT without judging it. The
# two wrappers below decide whether a non-zero exit ends the whole setup
# (capture_step) or only the account currently being swept
# (capture_optional_step).
run_capture_step() {
  seconds="$1"
  display="$2"
  shift 2
  automatic_recovery="${NMTK_SETUP_AUTOMATIC_RECOVERY:-false}"
  step_marker start "$seconds" "$automatic_recovery" "$display"
  printf -v rendered_command '%q ' "$@"
  rendered_command="${rendered_command% }"
  command_marker "$rendered_command"
  output_dir="$(mktemp -d /tmp/nmtk-command-output.XXXXXX)"
  TEMP_COMMAND_DIRS+=("$output_dir")
  stdout_file="$output_dir/stdout"
  stderr_file="$output_dir/stderr"
  stdout_pipe="$output_dir/stdout.pipe"
  stderr_pipe="$output_dir/stderr.pipe"
  mkfifo "$stdout_pipe" "$stderr_pipe"
  tee "$stdout_file" <"$stdout_pipe" &
  stdout_tee_pid="$!"
  tee "$stderr_file" <"$stderr_pipe" >&2 &
  stderr_tee_pid="$!"
  set +e
  timeout --signal=TERM --kill-after=5s "${seconds}s" "$@" \
    </dev/null >"$stdout_pipe" 2>"$stderr_pipe" &
  command_group_pid="$!"
  wait "$command_group_pid"
  command_exit="$?"
  terminate_residual_command_group "$command_group_pid"
  drain_capture_streams "$stdout_tee_pid" "$stderr_tee_pid"
  set -e
  STEP_OUTPUT="$(cat "$stdout_file")"
  STEP_ERROR="$(cat "$stderr_file")"
  rm -rf -- "$output_dir"
  if [ "$stdout_tee_exit" -ne 0 ] || [ "$stderr_tee_exit" -ne 0 ]; then
    fail "unexpected_setup_failure" 28 \
      "The server output stream could not be captured."
  fi
  STEP_EXIT="$command_exit"
  step_marker finish "$seconds" "$automatic_recovery" "$display"
  if [ "$command_exit" -ne 0 ]; then
    if [ "$command_exit" -eq 124 ]; then
      command_exit_marker timeout "$seconds"
    else
      command_exit_marker exit "$command_exit"
    fi
  fi
}

capture_step() {
  code="$2"
  failure_exit="$3"
  step_display="$4"
  run_capture_step "$1" "$4" "${@:6}"
  if [ "$STEP_EXIT" -ne 0 ]; then
    fail "$code" "$failure_exit" "$step_display failed or timed out."
  fi
}

# Same capture, but a non-zero exit is reported to the caller instead of ending
# setup. Used only while sweeping other accounts' rootless Podman storage, where
# one unreadable account must not block the whole server.
capture_optional_step() {
  run_capture_step "$1" "$2" "${@:3}"
  [ "$STEP_EXIT" -eq 0 ]
}

validated_container_ids() {
  local input="$1"
  local context="$2"
  local valid
  valid="$(printf '%s\n' "$input" |
    awk 'NF && $0 ~ /^[0-9a-fA-F]+$/ &&
      length($0) >= 12 && length($0) <= 64 {print}' | sort -u)"
  malformed="$(printf '%s\n' "$input" |
    awk 'NF && ($0 !~ /^[0-9a-fA-F]+$/ ||
      length($0) < 12 || length($0) > 64) {print; exit}')"
  if [ -n "$malformed" ]; then
    [ "$RUNTIME_SWEEP_OPTIONAL" -eq 0 ] || return 1
    fail "podman_inspection_failed" 29 \
      "$context returned an invalid container identifier."
  fi
  printf '%s' "$valid"
}

validated_volume_names() {
  local input="$1"
  local context="$2"
  local valid
  valid="$(printf '%s\n' "$input" |
    awk 'NF && $0 ~ /^[A-Za-z0-9][A-Za-z0-9_.-]*$/ {print}' | sort -u)"
  malformed="$(printf '%s\n' "$input" |
    awk 'NF && $0 !~ /^[A-Za-z0-9][A-Za-z0-9_.-]*$/ {print; exit}')"
  if [ -n "$malformed" ]; then
    [ "$RUNTIME_SWEEP_OPTIONAL" -eq 0 ] || return 1
    fail "volume_cleanup_failed" 31 \
      "$context returned an invalid volume name."
  fi
  printf '%s' "$valid"
}

if [ "$(id -u)" -ne 0 ]; then
  terminal "✗ Administrator privileges were not granted"
  fail "sudo_access_denied" 19 \
    "The setup shell is not running with administrator privileges."
fi
terminal "✓ Administrator privileges confirmed"

phase "preflight_running" 7 "Checking server compatibility"
capture_step 30 "unsupported_os" 20 "Checking server operating system" \
  "Server operating system identified" uname -s
[ "$STEP_OUTPUT" = "Linux" ] || {
  terminal "✗ Linux is required; found $STEP_OUTPUT"
  fail "unsupported_os" 20 "Linux is required."
}
capture_step 30 "insufficient_disk" 21 "Checking free disk space" \
  "Disk capacity checked" df -Pk /
AVAILABLE_KB="$(printf '%s\n' "$STEP_OUTPUT" | awk 'NR==2 {print $4}')"
[ "${AVAILABLE_KB:-0}" -ge 5242880 ] || {
  terminal "✗ Less than 5 GB is available on the server"
  fail "insufficient_disk" 21 "At least 5 GB of free disk space is required."
}

# Read-only inspection step. Takes the same arguments as capture_step, but while
# RUNTIME_SWEEP_OPTIONAL is set it reports failure to the caller instead of
# ending setup, so an unreadable third-party account is skipped rather than
# treated as a broken server. Destructive steps never go through here.
inspect_step() {
  if [ "$RUNTIME_SWEEP_OPTIONAL" -eq 1 ]; then
    capture_optional_step "$1" "$4" "${@:6}"
  else
    capture_step "$@"
  fi
}

remove_runtime_objects() {
  local runtime="$1"
  local context="$2"
  shift 2
  command -v "$runtime" >/dev/null 2>&1 || return 0
  if [ "$runtime" = "docker" ]; then
    inspect_step 20 "${runtime}_inspection_failed" 29 \
      "Checking $context access" "$context is accessible" \
      "$@" "$runtime" info --format \
      'version={{.ServerVersion}} rootless=false storage={{.DockerRootDir}}' ||
      return 1
  else
    inspect_step 20 "${runtime}_inspection_failed" 29 \
      "Checking $context access" "$context is accessible" \
      "$@" "$runtime" info --format \
      'version={{.Version.Version}} rootless={{.Host.Security.Rootless}} storage={{.Store.GraphRoot}}' ||
      return 1
  fi
  inspect_step 60 "${runtime}_inspection_failed" 29 \
    "Inspecting $context containers" "$context containers inspected" \
    "$@" "$runtime" ps -a --format '{{.ID}} {{.Names}}' || return 1
  known_ids="$(printf '%s\n' "$STEP_OUTPUT" |
    awk '$1 ~ /^[0-9a-fA-F]+$/ &&
      length($1) >= 12 && length($1) <= 64 &&
      $2 ~ /^(nmtk|nmtk-deploy|deploy)[_-](suite_api|neurosense-hw-worker|neurobench-runner-worker|neurochip-hw-worker|lava-backend|launcher-control|neurocnl-physics-worker|snn-mlir-compiler|jupyter-server)([-_][0-9]+)?$/ {print $1}')"
  if [ -n "$known_ids" ]; then
    known_id_list=()
    while IFS= read -r object_id; do
      [ -n "$object_id" ] && known_id_list+=("$object_id")
    done <<<"$known_ids"
    capture_step 60 "container_cleanup_failed" 30 \
      "Removing known NMTK $runtime containers" \
      "Known NMTK $runtime containers removed" \
      "$@" "$runtime" rm -f "${known_id_list[@]}"
  fi
  for project in $PROJECTS; do
    inspect_step 60 "${runtime}_inspection_failed" 29 \
      "Inspecting NMTK $runtime project $project" \
      "$context project $project inspected" \
      "$@" "$runtime" ps -aq \
      --filter "label=com.docker.compose.project=$project" || return 1
    ids="$STEP_OUTPUT"
    inspect_step 60 "${runtime}_inspection_failed" 29 \
      "Inspecting legacy NMTK $runtime project $project" \
      "$context legacy project $project inspected" \
      "$@" "$runtime" ps -aq \
      --filter "label=io.podman.compose.project=$project" || return 1
    ids="$ids
$STEP_OUTPUT"
    ids="$(validated_container_ids "$ids" \
      "$context project $project inspection")" || {
      # The validator runs in a subshell, so its own exit cannot end the script.
      validation_exit="$?"
      [ "$RUNTIME_SWEEP_OPTIONAL" -eq 1 ] && return 1
      exit "$validation_exit"
    }
    if [ -n "$ids" ]; then
      id_list=()
      while IFS= read -r object_id; do
        [ -n "$object_id" ] && id_list+=("$object_id")
      done <<<"$ids"
      capture_step 60 "container_cleanup_failed" 30 \
        "Removing NMTK $runtime project $project" \
        "NMTK $runtime project $project removed" \
        "$@" "$runtime" rm -f "${id_list[@]}"
    fi
    if [ "$FACTORY_RESET" = "true" ]; then
      inspect_step 60 "${runtime}_inspection_failed" 29 \
        "Inspecting NMTK $runtime data for project $project" \
        "$context project $project volumes inspected" \
        "$@" "$runtime" volume ls -q \
        --filter "label=com.docker.compose.project=$project" || return 1
      volumes="$STEP_OUTPUT"
      inspect_step 60 "${runtime}_inspection_failed" 29 \
        "Inspecting legacy NMTK $runtime data for project $project" \
        "$context legacy project $project volumes inspected" \
        "$@" "$runtime" volume ls -q \
        --filter "label=io.podman.compose.project=$project" || return 1
      volumes="$volumes
$STEP_OUTPUT"
      volumes="$(validated_volume_names "$volumes" \
        "$context project $project volume inspection")" || {
        validation_exit="$?"
        [ "$RUNTIME_SWEEP_OPTIONAL" -eq 1 ] && return 1
        exit "$validation_exit"
      }
      if [ -n "$volumes" ]; then
        volume_list=()
        while IFS= read -r volume_name; do
          [ -n "$volume_name" ] && volume_list+=("$volume_name")
        done <<<"$volumes"
        capture_step 60 "volume_cleanup_failed" 31 \
          "Erasing NMTK $runtime data for project $project" \
          "NMTK $runtime volumes removed" \
          "$@" "$runtime" volume rm -f "${volume_list[@]}"
      fi
    fi
  done
}

phase "reconciling_existing_install" 10 \
  "Removing existing NMTK containers"
if command -v docker >/dev/null 2>&1; then
  capture_step 30 "docker_inspection_failed" 29 "Starting Docker service" \
    "Docker service started" systemctl start docker
  remove_runtime_objects docker docker
fi
if command -v podman >/dev/null 2>&1; then
  remove_runtime_objects podman podman
  while IFS=: read -r candidate _ uid gid _ home _; do
    [ "$uid" -ge 1000 ] 2>/dev/null || continue
    [ -d "$home" ] || continue

    configured_storage="$home/.config/containers/storage.conf"
    default_storage="$home/.local/share/containers/storage"
    active_runtime="$RUNTIME_BASE/$uid"
    if [ ! -e "$configured_storage" ] &&
       [ ! -d "$default_storage" ] &&
       [ ! -S "$active_runtime/podman/podman.sock" ] &&
       [ ! -d "$active_runtime/libpod" ]; then
      continue
    fi

    # Everything below concerns somebody else's rootless Podman. A problem here
    # says nothing about whether this server can host NMTK, so the account is
    # skipped and named instead of failing the whole setup.
    RUNTIME_SWEEP_OPTIONAL=1
    skip_candidate=0
    runtime_dir="$active_runtime"
    if [ -d "$runtime_dir" ]; then
      runtime_owner="$(stat -c '%u' "$runtime_dir" 2>/dev/null || true)"
      if [ "$runtime_owner" != "$uid" ]; then
        skip_candidate=1
      fi
    elif capture_optional_step 30 \
        "Preparing Podman access for user $candidate" \
        mktemp -d "/tmp/nmtk-podman-runtime.${uid}.XXXXXX"; then
      runtime_dir="$STEP_OUTPUT"
      TEMP_RUNTIME_DIRS+=("$candidate:$runtime_dir")
      capture_optional_step 30 \
        "Securing Podman access for user $candidate" \
        bash -c 'chown "$1:$2" "$3" && chmod 700 "$3"' \
        _ "$uid" "$gid" "$runtime_dir" || skip_candidate=1
    else
      skip_candidate=1
    fi

    if [ "$skip_candidate" -eq 0 ]; then
      remove_runtime_objects podman "podman (user $candidate)" \
        runuser -u "$candidate" -- \
        env "HOME=$home" "XDG_RUNTIME_DIR=$runtime_dir" || skip_candidate=1
    fi
    RUNTIME_SWEEP_OPTIONAL=0

    if [ "$skip_candidate" -eq 1 ]; then
      SKIPPED_PODMAN_ACCOUNTS="$SKIPPED_PODMAN_ACCOUNTS $candidate"
      printf 'Could not read the Podman setup of account %s; its containers were left in place.\n' \
        "$candidate"
    fi
  done </etc/passwd
  if [ -n "$SKIPPED_PODMAN_ACCOUNTS" ]; then
    printf 'Skipped Podman accounts:%s\n' "$SKIPPED_PODMAN_ACCOUNTS"
  fi
fi

phase "installing_prerequisites" 13 "Preparing $ENGINE"
case "$ENGINE" in
  docker)
    if ! command -v docker >/dev/null 2>&1; then
      command -v curl >/dev/null 2>&1 ||
        capture_step 300 "engine_install_failed" 24 \
          "Installing server download support" "curl installed" \
          bash -c 'apt-get update -qq &&
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl'
      capture_step 300 "engine_install_failed" 24 \
        "Installing Docker Engine" "Docker Engine installed" \
        bash -c 'curl -fsSL https://get.docker.com | sh'
    fi
    capture_step 30 "engine_install_failed" 24 \
      "Enabling Docker service" "Docker service enabled" \
      systemctl enable --now docker
    ;;
  podman)
    if ! command -v podman >/dev/null 2>&1; then
      command -v apt-get >/dev/null 2>&1 ||
        fail "unsupported_os" 22 \
          "apt-get is required for automatic Podman installation."
      capture_step 300 "engine_install_failed" 24 \
        "Installing Podman and Compose support" \
        "Podman and its Compose provider installed" \
        bash -c 'apt-get update -qq &&
          DEBIAN_FRONTEND=noninteractive apt-get install -y -qq podman podman-compose'
    fi
    capture_step 20 "podman_inspection_failed" 29 \
      "Checking Podman Compose support" "Podman Compose provider is available" \
      podman compose version
    ;;
  *)
    fail "engine_install_failed" 23 "Unsupported container engine: $ENGINE."
    ;;
esac

phase "bootstrapping_access" 17 "Preparing the NMTK deployment account"
if getent group "$DEPLOY_GROUP" >/dev/null 2>&1; then
  terminal "✓ Deployment group already exists"
else
  capture_step 30 "deploy_account_failed" 25 \
    "Creating NMTK deployment group" "Deployment group created" \
    groupadd "$DEPLOY_GROUP"
fi
if id "$DEPLOY_USER" >/dev/null 2>&1; then
  terminal "✓ Deployment account already exists"
  capture_step 30 "deploy_account_failed" 25 \
    "Aligning NMTK deployment account" "Deployment account aligned" \
    usermod --gid "$DEPLOY_GROUP" "$DEPLOY_USER"
else
  capture_step 30 "deploy_account_failed" 25 \
    "Creating NMTK deployment account" "Deployment account created" \
    useradd --create-home --shell /bin/bash --gid "$DEPLOY_GROUP" "$DEPLOY_USER"
fi
capture_step 30 "deploy_account_failed" 25 \
  "Removing legacy deployment permissions" "Legacy sudo rule removed" \
  rm -f /etc/sudoers.d/nmtk-deploy
if getent group docker >/dev/null 2>&1; then
  capture_step 30 "deploy_account_failed" 25 \
    "Granting deployment account Docker access" \
    "Deployment account can access Docker" \
    usermod -aG docker "$DEPLOY_USER"
fi

DEPLOY_HOME="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
DEPLOY_UID="$(id -u "$DEPLOY_USER")"
case "$DEPLOY_HOME" in
  /*) ;;
  *)
    terminal "✗ Deployment account has no valid home directory"
    fail "deploy_account_failed" 25 \
      "The deployment account has no valid home directory."
    ;;
esac
[ "$DEPLOY_HOME" != "/" ] || {
  terminal "✗ Deployment account cannot use the filesystem root as its home"
  fail "deploy_account_failed" 25 \
    "The deployment account cannot use the filesystem root as its home."
}
if [ ! -d "$DEPLOY_HOME" ]; then
  capture_step 30 "deploy_account_failed" 25 \
    "Creating NMTK deployment home" "Deployment home created" \
    install -d -m 750 -o "$DEPLOY_USER" -g "$DEPLOY_GROUP" "$DEPLOY_HOME"
fi
capture_step 30 "deploy_account_failed" 26 \
  "Preparing deployment credential workspace" \
  "Deployment credential workspace prepared" \
  mktemp -d /tmp/nmtk-deploy-key.XXXXXX
TEMPORARY_KEY_DIR="$STEP_OUTPUT"
TEMPORARY_KEY="$TEMPORARY_KEY_DIR/id_ed25519"
capture_step 30 "deploy_account_failed" 26 \
  "Generating a new deployment credential" "Deployment credential generated" \
  ssh-keygen -q -t ed25519 -N "" -f "$TEMPORARY_KEY"
capture_step 30 "deploy_account_failed" 26 \
  "Preparing deployment account SSH access" "Deployment SSH directory prepared" \
  install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_GROUP" "$DEPLOY_HOME/.ssh"
capture_step 30 "deploy_account_failed" 26 \
  "Installing the new deployment credential" "Deployment public key installed" \
  install -m 600 -o "$DEPLOY_USER" -g "$DEPLOY_GROUP" \
  "$TEMPORARY_KEY.pub" "$DEPLOY_HOME/.ssh/authorized_keys"

if [ "$ENGINE" = "podman" ]; then
  capture_step 30 "deploy_account_failed" 27 \
    "Enabling persistent rootless Podman access" \
    "Deployment account lingering enabled" \
    loginctl enable-linger "$DEPLOY_USER"
  capture_step 30 "deploy_account_failed" 27 \
    "Starting the deployment account service manager" \
    "Deployment account service manager started" \
    systemctl start "user@$DEPLOY_UID.service"
  capture_step 30 "deploy_account_failed" 27 \
    "Preparing rootless Podman runtime" \
    "Rootless Podman runtime directory prepared" \
    install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_GROUP" \
    "/run/user/$DEPLOY_UID"
  NMTK_SETUP_AUTOMATIC_RECOVERY=true \
  capture_step 30 "podman_api_start_failed" 27 \
    "Starting or repairing rootless Podman API" \
    "Rootless Podman API started" \
    runuser -u "$DEPLOY_USER" -- env \
      "HOME=$DEPLOY_HOME" "XDG_RUNTIME_DIR=/run/user/$DEPLOY_UID" \
      bash -c '
        socket="$XDG_RUNTIME_DIR/podman/podman.sock"
        remote_url="unix://$socket"
        # Non-interactive SSH sessions commonly have no user D-Bus even after
        # lingering is enabled. Persist the socket when systemd is available,
        # but never let that optional path block the detached Podman fallback.
        timeout --signal=TERM --kill-after=1s 5s \
          systemctl --user enable podman.socket >/dev/null 2>&1 || true
        timeout --signal=TERM --kill-after=1s 5s \
          systemctl --user start podman.socket >/dev/null 2>&1 || true
        for attempt in 1 2 3 4 5; do
          if [ -S "$socket" ] &&
             podman --remote --url "$remote_url" info --format \
               "version={{.Version.Version}} rootless={{.Host.Security.Rootless}} storage={{.Store.GraphRoot}}"; then
            exit 0
          fi
          sleep 0.4
        done

        timeout --signal=TERM --kill-after=1s 5s \
          systemctl --user stop podman.socket >/dev/null 2>&1 || true
        mkdir -p "$XDG_RUNTIME_DIR/podman"
        rm -f -- "$socket"
        command -v setsid >/dev/null 2>&1 || {
          printf "setsid is required to start the fallback Podman service\n" >&2
          exit 1
        }
        setsid -f podman system service --time=0 "$remote_url" \
          </dev/null >"$HOME/.nmtk-podman-service.log" 2>&1
        for attempt in 1 2 3 4 5 6 7 8 9 10; do
          if [ -S "$socket" ] &&
             podman --remote --url "$remote_url" info --format \
               "version={{.Version.Version}} rootless={{.Host.Security.Rootless}} storage={{.Store.GraphRoot}}"; then
            exit 0
          fi
          sleep 0.5
        done
        printf "The rootless Podman API did not become ready after automatic recovery.\n" >&2
        exit 1'
  capture_step 20 "podman_api_start_failed" 27 \
    "Verifying rootless Podman API" "Rootless Podman API is ready" \
    runuser -u "$DEPLOY_USER" -- env \
      "HOME=$DEPLOY_HOME" "XDG_RUNTIME_DIR=/run/user/$DEPLOY_UID" \
      bash -c 'socket="$XDG_RUNTIME_DIR/podman/podman.sock"
      for attempt in 1 2 3 4 5 6 7 8 9 10; do
        if [ -S "$socket" ] &&
           podman --remote --url "unix://$socket" info --format \
             "version={{.Version.Version}} rootless={{.Host.Security.Rootless}} storage={{.Store.GraphRoot}}"; then
          exit 0
        fi
        sleep 1
      done
      exit 1'
fi

step_marker start 40 false "Finalizing secure deployment handoff"
set +e
PRIVATE_KEY_B64="$(
  timeout --signal=TERM --kill-after=1s 5s \
    base64 <"$TEMPORARY_KEY" | tr -d '\n'
)"
key_encode_exit="$?"
set -e
[ "$key_encode_exit" -eq 0 ] ||
  fail "deploy_account_failed" 26 \
    "The generated deployment credential could not be secured for handoff."

for runtime_entry in "${TEMP_RUNTIME_DIRS[@]-}"; do
  [ -n "$runtime_entry" ] || continue
  runtime_user="${runtime_entry%%:*}"
  runtime_dir="${runtime_entry#*:}"
  [ -n "$runtime_dir" ] || continue
  case "$runtime_dir" in
    /tmp/nmtk-podman-runtime.*)
      set +e
      timeout --signal=TERM --kill-after=1s 10s rm -rf -- "$runtime_dir"
      cleanup_exit="$?"
      set -e
      [ "$cleanup_exit" -eq 0 ] ||
        fail "podman_inspection_failed" 29 \
          "The temporary Podman runtime for user $runtime_user could not be removed."
      ;;
  esac
done
TEMP_RUNTIME_DIRS=()

set +e
timeout --signal=TERM --kill-after=1s 10s \
  rm -rf -- "$TEMPORARY_KEY_DIR"
key_cleanup_exit="$?"
set -e
[ "$key_cleanup_exit" -eq 0 ] ||
  fail "deploy_account_failed" 26 \
    "The temporary deployment credential directory could not be removed."
TEMPORARY_KEY_DIR=""

terminal "✓ Server preparation completed"
printf 'NMTK_DEPLOY_PRIVATE_KEY_B64=%s\n' "$PRIVATE_KEY_B64"
unset PRIVATE_KEY_B64
step_marker finish 40 false "Finalizing secure deployment handoff"
'''
        .replaceAll('__ENGINE__', containerEngine)
        .replaceAll(
          '__FACTORY_RESET__',
          resetFlag,
        );
  }

  Future<SSHRunResult> _runAdministratorScript(
    SSHClient client, {
    required String script,
    required String rootUsername,
    required String rootPassword,
    required String jobId,
    required List<String> redactionSecrets,
    Future<void> Function(
      DeploymentPhase phase,
      double percent,
      String label,
    )? onPhase,
    Future<void> Function(DeploymentActiveOperation? operation)? onOperation,
    Future<void> Function(String line)? onTerminalOutput,
  }) async {
    final needsSudo = rootUsername != 'root';
    final session = await client.execute(
      administratorShellCommand(needsSudo: needsSudo),
    );
    _administratorOperations[jobId] = _AdministratorOperation(client, session);
    Timer? idleWatchdog;
    try {
      final stdoutLines = <String>[];
      final stderrLines = <String>[];
      final operationTimeout = Completer<DeploymentFailureDetails>();
      final scriptCompleted = Completer<int>();
      var currentPhase = DeploymentPhase.bootstrappingAccess.wireName;
      var streamedUpdates = Future<void>.value();
      DeploymentActiveOperation? activeOperation;
      var activeOperationTimeoutSeconds = 0;

      // Every line the server prints rearms this timer, so no part of the
      // bootstrap is left unguarded. The previous watchdog was armed only
      // between a step's start and finish markers, which left the gaps between
      // steps — and the whole tail after the last step — able to hang forever.
      void armIdleWatchdog() {
        idleWatchdog?.cancel();
        if (scriptCompleted.isCompleted || operationTimeout.isCompleted) return;
        final operation = activeOperation;
        final seconds = operation == null
            ? _bootstrapIdleTimeoutSeconds
            : activeOperationTimeoutSeconds + 7;
        idleWatchdog = Timer(Duration(seconds: seconds), () {
          if (operationTimeout.isCompleted || scriptCompleted.isCompleted) {
            return;
          }
          operationTimeout.complete(
            operation == null
                ? _administratorStallDetails(phase: currentPhase)
                : _administratorStepTimeoutDetails(
                    label: operation.label,
                    timeoutSeconds: activeOperationTimeoutSeconds,
                    phase: currentPhase,
                  ),
          );
          session.kill(SSHSignal.TERM);
          session.close();
          client.close();
        });
      }

      void handleLine(String line, List<String> destination) {
        destination.add(line);
        final doneMarker =
            RegExp(r'^NMTK_SETUP_DONE\|(-?\d+)$').firstMatch(line);
        if (doneMarker != null) {
          idleWatchdog?.cancel();
          if (!scriptCompleted.isCompleted) {
            scriptCompleted.complete(int.parse(doneMarker.group(1)!));
          }
          return;
        }
        armIdleWatchdog();
        final phaseMarker = RegExp(
          r'^NMTK_SETUP_PHASE\|([^|]+)\|([^|]+)\|(.+)$',
        ).firstMatch(line);
        if (phaseMarker != null && onPhase != null) {
          currentPhase = phaseMarker.group(1) ?? currentPhase;
          final phase = DeploymentPhase.values.firstWhere(
            (candidate) => candidate.wireName == phaseMarker.group(1),
            orElse: () => DeploymentPhase.bootstrappingAccess,
          );
          streamedUpdates = streamedUpdates.then(
            (_) => onPhase(
              phase,
              double.tryParse(phaseMarker.group(2) ?? '') ?? 5,
              phaseMarker.group(3) ?? 'Preparing server',
            ),
          );
          return;
        }
        final operationMarker = _bootstrapOperationMarker(line);
        if (operationMarker != null) {
          DeploymentActiveOperation? operation;
          if (operationMarker.state == 'start') {
            operation = DeploymentActiveOperation(
              label: operationMarker.label,
              startedAt: DateTime.now(),
              timeoutSeconds: operationMarker.timeoutSeconds,
              automaticRecovery: operationMarker.automaticRecovery,
            );
            activeOperationTimeoutSeconds = operationMarker.timeoutSeconds;
          }
          activeOperation = operation;
          armIdleWatchdog();
          if (onOperation != null) {
            streamedUpdates = streamedUpdates.then(
              (_) => onOperation(operation),
            );
          }
          return;
        }
        if (onTerminalOutput == null) return;
        final safeLine = _bootstrapTranscriptLine(
          line,
          rootPassword: redactionSecrets.elementAtOrNull(0) ?? '',
          rootPrivateKey: redactionSecrets.elementAtOrNull(1) ?? '',
        );
        if (safeLine != null && safeLine.isNotEmpty) {
          streamedUpdates =
              streamedUpdates.then((_) => onTerminalOutput(safeLine));
        }
      }

      final stdout = session.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => handleLine(line, stdoutLines));
      final stderr = session.stderr
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => handleLine(line, stderrLines));
      final input = needsSudo && rootPassword.isNotEmpty
          ? '$rootPassword\n$script'
          : script;
      session.stdin.add(Uint8List.fromList(utf8.encode(input)));
      await session.stdin.close();
      armIdleWatchdog();
      // The script announcing its own exit is authoritative. Channel EOF is
      // not: sshd holds the channel open until every process that inherited
      // this session's stdout and stderr has exited, and preparing rootless
      // Podman deliberately leaves lingering processes behind.
      final outcome = await Future.any<Object>([
        scriptCompleted.future.then<Object>(_AdministratorSessionExit.new),
        session
            .waitForExit(timeout: const Duration(minutes: 12))
            .then<Object>(_AdministratorSessionExit.new),
        operationTimeout.future,
      ]);
      idleWatchdog?.cancel();
      if (outcome is DeploymentFailureDetails) {
        await Future.wait<void>([
          stdout.cancel(),
          stderr.cancel(),
        ]);
        await _settleStreamedUpdates(streamedUpdates);
        throw _RemoteSetupException(outcome);
      }
      final exitCode = (outcome as _AdministratorSessionExit).exitCode;
      if (exitCode == null && session.exitSignal == null) {
        session.kill(SSHSignal.TERM);
        session.close();
        client.close();
        await Future.wait<void>([
          stdout.cancel(),
          stderr.cancel(),
        ]);
        await _settleStreamedUpdates(streamedUpdates);
        throw const _RemoteSetupException(
          DeploymentFailureDetails(
            code: 'administrator_session_timeout',
            phase: 'bootstrapping_access',
            summary: 'Administrator setup timed out',
            recovery:
                'Open the terminal output to identify the command that timed out, then retry.',
          ),
        );
      }
      await _drainTranscriptStreams(stdout, stderr);
      session.close();
      await _settleStreamedUpdates(streamedUpdates);
      final stdoutBytes = utf8.encode(stdoutLines.join('\n'));
      final stderrBytes = utf8.encode(stderrLines.join('\n'));
      return SSHRunResult(
        output: Uint8List.fromList([...stdoutBytes, ...stderrBytes]),
        exitCode: exitCode ?? 1,
        stdout: Uint8List.fromList(stdoutBytes),
        stderr: Uint8List.fromList(stderrBytes),
        exitSignal: session.exitSignal,
      );
    } finally {
      idleWatchdog?.cancel();
      if (identical(_administratorOperations[jobId]?.session, session)) {
        _administratorOperations.remove(jobId);
      }
    }
  }

  /// Waits for the transcript streams to close, but never longer than
  /// [_administratorDrainTimeout].
  ///
  /// A held-open channel is expected here rather than exceptional: the
  /// deployment account's rootless Podman service and its pause processes
  /// inherit this session's descriptors and outlive the script on purpose. Both
  /// streams have already delivered every line the script printed, so nothing is
  /// lost by giving up on EOF.
  static Future<void> _drainTranscriptStreams(
    StreamSubscription<String> stdout,
    StreamSubscription<String> stderr, {
    Duration timeout = _administratorDrainTimeout,
  }) async {
    try {
      await Future.wait<void>([
        stdout.asFuture<void>(),
        stderr.asFuture<void>(),
      ]).timeout(timeout);
    } on TimeoutException {
      // Expected when a lingering server process still holds the channel.
    } on Object {
      // The exit status already decided the outcome; a late channel error
      // cannot invalidate output that was delivered line by line.
    } finally {
      await Future.wait<void>([stdout.cancel(), stderr.cancel()]);
    }
  }

  @visibleForTesting
  static Future<void> drainTranscriptStreamsForTesting(
    StreamSubscription<String> stdout,
    StreamSubscription<String> stderr, {
    Duration timeout = _administratorDrainTimeout,
  }) =>
      _drainTranscriptStreams(stdout, stderr, timeout: timeout);

  /// Lets the queued progress callbacks finish without letting a wedged write
  /// block the deployment. Errors still propagate.
  static Future<void> _settleStreamedUpdates(
    Future<void> streamedUpdates, {
    Duration timeout = _streamedUpdateSettleTimeout,
  }) =>
      streamedUpdates.timeout(timeout, onTimeout: () {});

  @visibleForTesting
  static Future<void> settleStreamedUpdatesForTesting(
    Future<void> streamedUpdates, {
    Duration timeout = _streamedUpdateSettleTimeout,
  }) =>
      _settleStreamedUpdates(streamedUpdates, timeout: timeout);

  @override
  Future<DeploymentJob> deploy(DeploymentRequest request) =>
      _deploy(request, persistTargetImmediately: true);

  Future<DeploymentJob> _deploy(
    DeploymentRequest request, {
    required bool persistTargetImmediately,
  }) async {
    final bundle = await _loadDeploymentBundle();
    final targetId = request.targetType == 'remote_host'
        ? 'remote-${request.host.trim().replaceAll('.', '-')}'
        : _newId('target');
    final jobId = _newId('deploy');
    final target = DeploymentTarget.fromJson(
      request.toPublicJson(id: targetId)
        ..['updatedAt'] = DateTime.now().toIso8601String(),
    );
    final store = await _store;
    if (persistTargetImmediately) {
      await store.saveTarget(target, request);
    } else {
      _pendingTargets[jobId] = target;
      _pendingRequests[jobId] = request;
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
    if (job.isTerminal) {
      _pendingTargets.remove(jobId);
      _pendingRequests.remove(jobId);
      return job;
    }
    if (_runningJobs.containsKey(jobId)) return job;

    final pendingTarget = _pendingTargets[jobId];
    final pendingRequest = _pendingRequests[jobId];
    final targets = await (await _store).loadTargets();
    final savedTargets =
        targets.where((candidate) => candidate.id == job.targetId);
    final target =
        pendingTarget ?? (savedTargets.isEmpty ? null : savedTargets.first);
    if (target == null) return job;
    final request =
        pendingRequest ?? await (await _store).requestForTarget(target);
    if (target.targetType == 'remote_host') {
      return _pollRemoteJob(job, target, request);
    }
    if (await _isApiReady(target)) {
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
    final bootstrapOperation = _administratorOperations.remove(jobId);
    final job = _jobs[jobId] ?? await fetchJob(jobId);
    if (bootstrapOperation != null) {
      bootstrapOperation.session.kill(SSHSignal.TERM);
      bootstrapOperation.session.close();
      bootstrapOperation.client.close();
      _pendingTargets.remove(jobId);
      _pendingRequests.remove(jobId);
      return _updateJob(
        job.copyWith(
          stage: DeploymentPhase.cancelled.wireName,
          stageLabel: 'Server setup cancelled',
          terminalOutput: _boundedTerminalOutput([
            ...job.terminalOutput,
            '[client: administrator setup cancelled]',
          ]),
          requiresEphemeralAdministrator: false,
          updatedAt: DateTime.now(),
        ),
      );
    }
    final pendingTarget = _pendingTargets[jobId];
    final pendingRequest = _pendingRequests[jobId];
    final targets = await (await _store).loadTargets();
    final matches = targets.where((target) => target.id == job.targetId);
    final target = pendingTarget ?? (matches.isEmpty ? null : matches.first);
    if (target != null && target.targetType == 'remote_host') {
      final request =
          pendingRequest ?? await (await _store).requestForTarget(target);
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
    _pendingTargets.remove(jobId);
    _pendingRequests.remove(jobId);
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

  @override
  Future<SystemHealthReport> diagnoseTarget(String targetId) async {
    final targets = await (await _store).loadTargets();
    final matches = targets.where((target) => target.id == targetId);
    if (matches.isEmpty) throw StateError('Unknown deployment target.');
    final target = matches.first;
    final host = target.host.isEmpty ? '127.0.0.1' : target.host;
    final checks = <SystemHealthCheck>[];

    try {
      final response = await _httpClient
          .post(
            Uri.parse(
              'http://$host:${target.backendPort}/api/suite/doctor',
            ),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'capabilities': const <String>['snntorch'],
            }),
          )
          .timeout(const Duration(seconds: 35));
      if (response.statusCode != 200) {
        throw StateError('Suite doctor returned HTTP ${response.statusCode}.');
      }
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Suite doctor returned invalid JSON.');
      }
      checks.addAll(SystemHealthReport.fromJson(payload).checks);
    } on Object {
      checks.add(
        const SystemHealthCheck(
          id: 'suite-api',
          label: 'NMTK backend',
          status: SystemHealthStatus.failed,
          detail: 'The NMTK backend is not serving requests.',
          recovery: 'Repair the saved server from System Health.',
          repairable: true,
        ),
      );
    }

    try {
      final response = await _httpClient
          .get(
            Uri.parse(
              'http://$host:$_launcherControlPort/api/launcher/doctor',
            ),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw StateError(
          'Launcher doctor returned HTTP ${response.statusCode}.',
        );
      }
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Launcher doctor returned invalid JSON.');
      }
      final fatalCount = payload['fatalCount'] as int? ?? 0;
      final degradedCount = payload['degradedCount'] as int? ?? 0;
      checks.add(
        SystemHealthCheck(
          id: 'launcher-control',
          label: 'Launcher control',
          status: fatalCount > 0
              ? SystemHealthStatus.failed
              : degradedCount > 0
                  ? SystemHealthStatus.degraded
                  : SystemHealthStatus.ok,
          detail: fatalCount > 0
              ? '$fatalCount required launcher check(s) failed.'
              : degradedCount > 0
                  ? '$degradedCount optional launcher capability check(s) are degraded.'
                  : 'Launcher control and required modules are ready.',
          recovery: fatalCount > 0
              ? 'Repair the saved server from System Health.'
              : '',
          repairable: fatalCount > 0,
        ),
      );
      final hosts = payload['akidaHosts'];
      if (hosts is! List<dynamic> || hosts.isEmpty) {
        checks.add(
          const SystemHealthCheck(
            id: 'akida-runtime',
            label: 'Akida runtime',
            status: SystemHealthStatus.notConfigured,
            detail: 'No Akida runtime is configured for this backend.',
            required: false,
          ),
        );
      } else {
        final hostMaps = hosts.whereType<Map<String, dynamic>>().toList();
        final allReady = hostMaps.isNotEmpty &&
            hostMaps.every((item) => item['state'] == 'ready');
        checks.add(
          SystemHealthCheck(
            id: 'akida-runtime',
            label: 'Akida runtime',
            status:
                allReady ? SystemHealthStatus.ok : SystemHealthStatus.degraded,
            detail: allReady
                ? 'The configured Akida runtime is ready.'
                : 'A configured Akida runtime needs attention.',
            recovery: allReady
                ? ''
                : 'Open Akida target management and run its preflight repair.',
            repairable: !allReady,
            required: false,
          ),
        );
      }
    } on Object {
      checks.add(
        const SystemHealthCheck(
          id: 'launcher-control',
          label: 'Launcher control',
          status: SystemHealthStatus.failed,
          detail: 'Launcher control is not serving requests.',
          recovery: 'Repair the saved server from System Health.',
          repairable: true,
        ),
      );
    }

    final overall = checks.any(
      (check) => check.required && check.status == SystemHealthStatus.failed,
    )
        ? SystemHealthStatus.failed
        : checks.any(
            (check) =>
                check.status == SystemHealthStatus.failed ||
                check.status == SystemHealthStatus.degraded,
          )
            ? SystemHealthStatus.degraded
            : SystemHealthStatus.ok;
    return SystemHealthReport(
      overall: overall,
      checkedAt: DateTime.now(),
      checks: checks,
    );
  }

  @override
  Future<SystemHealthReport> repairTarget(String targetId) async {
    final targets = await (await _store).loadTargets();
    final matches = targets.where((target) => target.id == targetId);
    if (matches.isEmpty) throw StateError('Unknown deployment target.');
    final target = matches.first;
    final request = await (await _store).requestForTarget(target);
    await _loadDeploymentBundle();

    if (target.targetType == 'remote_host') {
      final client = await _connect(request);
      try {
        final deployDir = await _remoteDeployDir(client);
        await _uploadAssetsForRepair(client, deployDir);
        await _runChecked(
          client,
          'cd ${_shellQuote(deployDir)} && '
              'bash ./nmtk-stack.sh install ${_shellQuote(request.containerEngine)} && '
              'bash ./nmtk-stack.sh start ${_shellQuote(request.containerEngine)}',
          'The server could not restart the NMTK backend.',
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
          '--no-build',
          '--remove-orphans',
        ],
        directory,
      );
    }
    await _waitForHealth(
      Uri.parse(
        'http://${target.host.isEmpty ? '127.0.0.1' : target.host}:${target.backendPort}/api/suite/health',
      ),
      attempts: 30,
    );
    return diagnoseTarget(targetId);
  }

  Future<void> _uploadAssetsForRepair(
    SSHClient client,
    String deployDir,
  ) async {
    final sftp = await client.sftp();
    for (final relative in _assetFiles) {
      final parent = path.posix.dirname(relative);
      if (parent != '.') {
        final result = await client.runWithResult(
          'mkdir -p ${_shellQuote(path.posix.join(deployDir, parent))}',
        );
        if (result.exitCode != 0) {
          throw StateError('Could not prepare the backend repair directory.');
        }
      }
      final data = await _assets.load('assets/deployment/$relative');
      final remote = await sftp.open(
        path.posix.join(deployDir, relative),
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.truncate |
            SftpFileOpenMode.write,
      );
      try {
        await remote.writeBytes(_exactAssetBytes(data));
      } finally {
        await remote.close();
      }
    }
  }

  @override
  Future<DeploymentJob> reinstallTarget(
    String targetId, {
    bool factoryReset = false,
  }) async {
    final targets = await (await _store).loadTargets();
    final matches = targets.where((target) => target.id == targetId);
    if (matches.isEmpty) throw StateError('Unknown deployment target.');
    final request = await (await _store).requestForTarget(
      matches.first,
      cleanInstall: factoryReset,
    );
    return deploy(request);
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
      final current = _jobs[job.id] ?? job;
      final safeError = redactForLogging(error.toString(), request);
      final existingConnectionReachable = request.targetType == 'remote_host'
          ? await _isApiReady(target)
          : null;
      final failure = DeploymentFailureDetails(
        code: 'deployment_phase_failed',
        phase: current.stage,
        summary: _failureSummaryForPhase(current.stage),
        recovery:
            safeError.replaceFirst(RegExp(r'^(Bad state|Exception):\s*'), ''),
        technicalDetails: _boundedDiagnosticOutput(safeError),
        existingConnectionReachable: existingConnectionReachable,
      );
      await _updateJob(
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

  Future<void> _startRemoteDeployment(
    DeploymentJob job,
    DeploymentTarget target,
    DeploymentRequest request,
    DeploymentAssetBundle bundle,
  ) async {
    final progressFloor = _jobs[job.id]?.percent ?? 0;
    await _emit(
      job,
      DeploymentPhase.connecting,
      progressFloor > 5 ? progressFloor : 5,
      'Connecting with SSH',
    );
    final client = await _connect(request);
    try {
      await _emit(
        job,
        DeploymentPhase.installingPrerequisites,
        progressFloor > 12 ? progressFloor : 12,
        'Preparing ${request.containerEngine}',
      );
      await _ensureRemoteEngine(client, request, job);
      final deployDir = await _remoteDeployDir(
        client,
        job: job,
        request: request,
      );
      final jobDir = '$deployDir/.jobs';
      await _runChecked(
        client,
        'mkdir -p ${_shellQuote(deployDir)} ${_shellQuote(jobDir)}',
        'Could not create the deployment directory.',
        job: job,
        request: request,
      );
      await _emit(
        job,
        DeploymentPhase.uploadingAssets,
        25,
        'Uploading deployment bundle v${bundle.version} '
        '(${_shortHash(bundle.manifestHash)})',
      );
      await _uploadAssets(
        client,
        deployDir,
        job: job,
        request: request,
      );
      await _verifyRemoteAssets(
        client,
        deployDir,
        bundle,
        job: job,
        request: request,
      );
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
        job: job,
        request: request,
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
      final result = await client
          .runWithResult(
            'cat ${_shellQuote('$jobDir/${job.id}.status')} 2>/dev/null; '
            'printf "\\n---NMTK-LOG---\\n"; '
            'tail -c 512000 ${_shellQuote('$jobDir/${job.id}.log')} 2>/dev/null',
          )
          .timeout(_statusPollTimeout);
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
      final remoteLogLines = sections.length > 1
          ? sections[1]
              .split('\n')
              .map((line) => redactForLogging(line, request))
              .where((line) => line.isNotEmpty)
              .toList(growable: false)
          : const <String>[];
      final percent = double.tryParse(status[1]) ?? job.percent;
      final stageLabel = status.sublist(2).join('|');
      final terminalOutput = _replaceRemoteInstallOutput(
        job.terminalOutput,
        remoteLogLines,
      );
      // Only real movement may refresh the progress clock. Stamping it on every
      // poll made the notifier's staleness watchdog unreachable, which is how a
      // dead deployment could keep looking alive indefinitely.
      final reportedProgress = stage != job.stage ||
          percent != job.percent ||
          stageLabel != job.stageLabel ||
          terminalOutput.length != job.terminalOutput.length;
      var next = job.copyWith(
        stage: stage,
        percent: percent,
        stageLabel: stageLabel,
        logs: logs,
        terminalOutput: terminalOutput,
        error: stage == DeploymentPhase.failed.wireName
            ? status.sublist(2).join('|')
            : '',
        updatedAt: DateTime.now(),
        lastProgressAt: reportedProgress ? DateTime.now() : job.lastProgressAt,
      );
      if (stage == DeploymentPhase.completed.wireName) {
        try {
          next = await _verifyRemoteApis(next, target);
        } catch (_) {
          next = _clientReachabilityFailure(next, target);
        }
      }
      if (next.stage == DeploymentPhase.completed.wireName &&
          _pendingRequests.containsKey(job.id)) {
        await (await _store).saveTarget(target, request);
        _pendingTargets.remove(job.id);
        _pendingRequests.remove(job.id);
      } else if (next.isTerminal) {
        _pendingTargets.remove(job.id);
        _pendingRequests.remove(job.id);
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
    DeploymentJob job,
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
      job: job,
      request: request,
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
        job: job,
        request: request,
      );
    } else {
      await _runChecked(
        client,
        '''
export XDG_RUNTIME_DIR="\${XDG_RUNTIME_DIR:-/run/user/\$(id -u)}"
export DOCKER_HOST="unix://\$XDG_RUNTIME_DIR/podman/podman.sock"
mkdir -p "\$XDG_RUNTIME_DIR/podman"
systemctl --user enable --now podman.socket >/dev/null 2>&1 ||
  (nohup podman system service --time=0 "\$DOCKER_HOST" >"\$HOME/.nmtk-podman-service.log" 2>&1 &)
for attempt in 1 2 3 4 5; do
  podman info >/dev/null 2>&1 && podman compose version >/dev/null 2>&1 && exit 0
  sleep 1
done
exit 1
''',
        'Podman is installed, but its rootless service or Compose provider '
            'is not ready.',
        job: job,
        request: request,
      );
    }
  }

  Future<String> _remoteDeployDir(
    SSHClient client, {
    DeploymentJob? job,
    DeploymentRequest? request,
  }) async {
    final result = job != null && request != null
        ? await _runRemoteCommand(
            client,
            'printf %s "\$HOME"',
            job: job,
            request: request,
          )
        : await client.runWithResult('printf %s "\$HOME"');
    final home = utf8.decode(result.stdout).trim();
    if (home.isEmpty) {
      throw StateError(
        'The SSH account has no home directory. Choose a normal login account.',
      );
    }
    return '$home/.nmtk/deploy';
  }

  Future<void> _uploadAssets(
    SSHClient client,
    String deployDir, {
    required DeploymentJob job,
    required DeploymentRequest request,
  }) async {
    final sftp = await client.sftp();
    for (final relative in _assetFiles) {
      final parent = path.posix.dirname(relative);
      if (parent != '.') {
        await _runChecked(
          client,
          'mkdir -p ${_shellQuote(path.posix.join(deployDir, parent))}',
          'Could not create a remote deployment directory.',
          job: job,
          request: request,
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
        await remote.writeBytes(_exactAssetBytes(data));
      } finally {
        await remote.close();
      }
    }
  }

  Future<DeploymentAssetBundle> _loadDeploymentBundle() async {
    try {
      final data =
          await _assets.load('assets/deployment/deployment-manifest.json');
      final bundle = DeploymentAssetBundle.fromManifestBytes(
        _exactAssetBytes(data),
      );
      final expectedFiles = _assetFiles
          .where((relative) => relative != 'deployment-manifest.json')
          .toSet();
      final manifestFiles = bundle.fileHashes.keys.toSet();
      final invalidFiles = <String>{
        ...expectedFiles.difference(manifestFiles),
        ...manifestFiles.difference(expectedFiles),
      };
      final sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

      for (final relative in expectedFiles.intersection(manifestFiles)) {
        final expectedHash = bundle.fileHashes[relative]!;
        if (!sha256Pattern.hasMatch(expectedHash)) {
          invalidFiles.add(relative);
          continue;
        }
        try {
          final asset = await _assets.load('assets/deployment/$relative');
          final actualHash = sha256.convert(_exactAssetBytes(asset)).toString();
          if (actualHash != expectedHash) invalidFiles.add(relative);
        } on Object {
          invalidFiles.add(relative);
        }
      }

      if (invalidFiles.isNotEmpty) {
        final sortedFiles = invalidFiles.toList()..sort();
        throw _DeploymentBundleIntegrityException(sortedFiles);
      }
      return bundle;
    } on _DeploymentBundleIntegrityException catch (error) {
      debugPrint(
        'NMTK deployment bundle integrity check failed for: '
        '${error.files.join(', ')}',
      );
      throw StateError(_bundleIntegrityRecovery);
    } on Object {
      debugPrint(
        'NMTK deployment bundle integrity check failed for: '
        'deployment-manifest.json',
      );
      throw StateError(_bundleIntegrityRecovery);
    }
  }

  static Uint8List _exactAssetBytes(ByteData data) =>
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

  Future<void> _verifyRemoteAssets(
    SSHClient client,
    String deployDir,
    DeploymentAssetBundle bundle, {
    required DeploymentJob job,
    required DeploymentRequest request,
  }) async {
    final files = <String>[
      ...bundle.fileHashes.keys,
      'deployment-manifest.json',
    ];
    final result = await _runRemoteCommand(
      client,
      'cd ${_shellQuote(deployDir)} && sha256sum '
      '${files.map(_shellQuote).join(' ')}',
      job: job,
      request: request,
    );
    if (result.exitCode != 0) {
      throw StateError('Could not verify uploaded deployment assets.');
    }
    final checksums = DeploymentAssetBundle.parseRemoteChecksumOutput(
      utf8.decode(result.stdout),
    );
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
      await file.writeAsBytes(_exactAssetBytes(data), flush: true);
    }
    return directory;
  }

  Future<DeploymentJob> _verifyRemoteApis(
    DeploymentJob job,
    DeploymentTarget target, {
    String? hostOverride,
    int attempts = 60,
  }) async {
    final host = hostOverride ?? target.host;
    final suiteReady = await _waitForHealth(
      Uri.parse('http://$host:${target.backendPort}/api/suite/health'),
      attempts: attempts,
    );
    if (!suiteReady) {
      throw StateError(
        'Suite API did not become ready at $host:${target.backendPort}.',
      );
    }
    final launcherReady = await _waitForHealth(
      Uri.parse('http://$host:$_launcherControlPort/health'),
      attempts: attempts,
    );
    if (!launcherReady) {
      throw StateError(
        'Launcher control did not become ready at $host:$_launcherControlPort.',
      );
    }
    final neuroStudioReady = await _waitForHealth(
      Uri.parse('http://$host:${target.backendPort}/api/neurocnl/health'),
      attempts: attempts,
    );
    if (!neuroStudioReady) {
      throw StateError(
          'NeuroStudio did not become ready on the deployed server.');
    }
    final modulesResponse = await _waitForResponse(
      Uri.parse(
        'http://$host:$_launcherControlPort/api/launcher/modules',
      ),
      attempts: attempts,
    );
    if (modulesResponse == null) {
      throw StateError('Launcher control did not return its module list.');
    }
    final modules = jsonDecode(modulesResponse.body);
    if (modules is! List ||
        !modules.any((module) =>
            module is Map<String, dynamic> && module['id'] == 'neurocnl')) {
      throw StateError('NeuroStudio is not available from launcher control.');
    }
    await _startAndVerifyNeuroStudio(host, target.backendPort,
        attempts: attempts);

    final jupyterReady = await _waitForHealth(
      Uri.parse('http://$host:8008/api/status'),
      attempts: 2,
    );
    var currentJob = job;
    final logs = [...currentJob.logs];
    if (!jupyterReady) {
      logs.add(
        'degraded optional capability: Jupyter is not ready; core services '
        'are available.',
      );
    }
    final optionalFailures = <String>[
      if (!jupyterReady) 'Jupyter is not ready',
    ];
    final akidaResult = await _updateSelectedAkidaRuntime(
      currentJob,
      Uri.parse('http://$host:$_launcherControlPort'),
    );
    currentJob = akidaResult.job;
    logs
      ..clear()
      ..addAll(currentJob.logs);
    if (akidaResult.failureMessage != null) {
      optionalFailures.add(akidaResult.failureMessage!);
      logs.add(
        'degraded optional capability: ${akidaResult.failureMessage}',
      );
    }
    final optionalCapabilityError = optionalFailures.isEmpty
        ? ''
        : 'degraded optional capability: ${optionalFailures.join('; ')}; '
            'core services are available.';
    return currentJob.copyWith(
      stage: DeploymentPhase.completed.wireName,
      percent: 100,
      stageLabel: 'Backend and launcher control are ready',
      logs: logs,
      error: optionalCapabilityError,
      updatedAt: DateTime.now(),
    );
  }

  Future<({DeploymentJob job, String? failureMessage})>
      _updateSelectedAkidaRuntime(
    DeploymentJob job,
    Uri launcherBase,
  ) async {
    Map<String, dynamic> settings;
    try {
      final response = await _httpClient
          .get(launcherBase.resolve('/api/launcher/settings'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) {
        return (
          job: job,
          failureMessage:
              'Akida target selection could not be read; retry the Akida update',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return (
          job: job,
          failureMessage:
              'Akida target selection could not be read; retry the Akida update',
        );
      }
      settings = decoded;
    } catch (_) {
      return (
        job: job,
        failureMessage:
            'Akida target selection could not be read; retry the Akida update',
      );
    }
    final selectedHostId = settings['selectedAkidaHostId'];
    if (selectedHostId is! String || selectedHostId.trim().isEmpty) {
      return (job: job, failureMessage: null);
    }

    final hostId = selectedHostId.trim();
    Map<String, dynamic> update;
    try {
      final response = await _httpClient
          .post(
            launcherBase.resolve(
              '/api/launcher/akida/hosts/$hostId/runtime-update-jobs',
            ),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return (
          job: job,
          failureMessage:
              'the selected Akida runtime update could not be started; retry it in Backend Setup',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return (
          job: job,
          failureMessage:
              'the selected Akida runtime returned an invalid update status; retry it in Backend Setup',
        );
      }
      update = decoded;
    } catch (_) {
      return (
        job: job,
        failureMessage:
            'the selected Akida host is offline or unreachable; retry the Akida update',
      );
    }

    for (var poll = 0; poll < 600; poll++) {
      final status = update['status']?.toString() ?? '';
      final message = update['message']?.toString().trim() ?? '';
      final progress = (update['progress'] as num?)?.toDouble() ?? 0;
      if (status == 'completed') {
        final version = update['installedVersion']?.toString().trim() ?? '';
        return (
          job: job.copyWith(
            logs: [
              ...job.logs,
              version.isEmpty
                  ? 'Selected Akida runtime is up to date.'
                  : 'Selected Akida runtime $version is up to date.',
            ],
          ),
          failureMessage: null,
        );
      }
      if (status == 'failed') {
        final recovery = update['recovery']?.toString().trim() ?? '';
        final safeMessage = message.isEmpty
            ? 'the selected Akida runtime update failed'
            : message;
        return (
          job: job,
          failureMessage:
              recovery.isEmpty ? safeMessage : '$safeMessage $recovery',
        );
      }

      final label =
          message.isEmpty ? 'Updating selected Akida runtime' : message;
      job = job.copyWith(
        stage: DeploymentPhase.updatingAkidaRuntime.wireName,
        percent: 94 + (progress.clamp(0, 100) * 0.05),
        stageLabel: label,
        logs: job.logs.isNotEmpty && job.logs.last == label
            ? job.logs
            : [...job.logs, label],
        updatedAt: DateTime.now(),
        lastProgressAt: DateTime.now(),
      );
      await _updateJob(job);
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        final response = await _httpClient
            .get(
              launcherBase.resolve(
                '/api/launcher/akida/hosts/$hostId/runtime-update-jobs/${update['jobId']}',
              ),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) update = decoded;
      } catch (_) {
        // A service restart can briefly close the launcher connection. Keep
        // polling the persisted job instead of turning that into a core
        // backend deployment failure.
      }
    }
    return (
      job: job,
      failureMessage:
          'the selected Akida runtime update timed out; retry it in Backend Setup',
    );
  }

  Future<bool> _isApiReady(DeploymentTarget target) async {
    final host = target.host.isEmpty ? '127.0.0.1' : target.host;
    return _waitForHealth(
      Uri.parse('http://$host:$_launcherControlPort/health'),
      attempts: 1,
    );
  }

  Future<bool> _waitForHealth(Uri uri, {int attempts = 60}) async {
    return (await _waitForResponse(uri, attempts: attempts)) != null;
  }

  Future<http.Response?> _waitForResponse(
    Uri uri, {
    required int attempts,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final response =
            await _httpClient.get(uri).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) return response;
      } catch (_) {
        // Startup connection failures are expected while containers warm.
      }
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    return null;
  }

  Future<void> _startAndVerifyNeuroStudio(
    String host,
    int backendPort, {
    required int attempts,
  }) async {
    final launcherBase = Uri.parse('http://$host:$_launcherControlPort');
    final startResponse = await _httpClient
        .post(launcherBase.resolve('/api/launcher/modules/neurocnl/start'))
        .timeout(const Duration(seconds: 4));
    if (startResponse.statusCode < 200 || startResponse.statusCode >= 300) {
      throw StateError('Launcher control could not start NeuroStudio.');
    }
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final response = await _httpClient
            .get(launcherBase.resolve('/api/launcher/modules/neurocnl'))
            .timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final module = jsonDecode(response.body);
          if (module is Map<String, dynamic>) {
            final status = module['status'];
            if (status == 4 || status == 7) return;
            if (status == 6) {
              throw StateError(
                  'NeuroStudio could not start on the deployed server.');
            }
          }
        }
      } catch (error) {
        if (error is StateError) rethrow;
      }
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    throw StateError(
        'NeuroStudio did not become ready on the deployed server.');
  }

  DeploymentJob _clientReachabilityFailure(
    DeploymentJob job,
    DeploymentTarget target,
  ) {
    const message =
        'The backend started on the server, but this Mac cannot reach it. '
        'Check that the server is online and reachable from this network, then retry.';
    return job.copyWith(
      stage: DeploymentPhase.failed.wireName,
      percent: 100,
      stageLabel: 'Backend is not reachable from this device',
      logs: [...job.logs, 'Client readiness check failed for ${target.host}.'],
      error: message,
      failureDetails: const DeploymentFailureDetails(
        code: 'client_readiness_failed',
        phase: 'verifying_suite_api',
        summary: 'Backend is not reachable from this device',
        recovery: message,
        technicalDetails:
            'Required client-facing health checks did not all return HTTP 200.',
        existingConnectionReachable: false,
      ),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _runChecked(
    SSHClient client,
    String command,
    String failureMessage, {
    DeploymentJob? job,
    DeploymentRequest? request,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final result = job != null && request != null
        ? await _runRemoteCommand(
            client,
            command,
            job: job,
            request: request,
            timeout: timeout,
          )
        : await client.runWithResult(command);
    if (result.exitCode == 0) return;
    final details = utf8.decode(result.output).trim();
    throw StateError(
      details.isEmpty ? failureMessage : '$failureMessage $details',
    );
  }

  Future<SSHRunResult> _runRemoteCommand(
    SSHClient client,
    String command, {
    required DeploymentJob job,
    required DeploymentRequest request,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    await _appendTerminalOutput(
      job.id,
      '\$ ${redactForLogging(command, request)}',
    );
    final session = await client.execute(
      'sh -c ${_shellQuote(command)} 2>&1',
    );
    final outputLines = <String>[];
    var streamedUpdates = Future<void>.value();

    void forward(String line) {
      outputLines.add(line);
      final safeLine = redactForLogging(line, request);
      streamedUpdates =
          streamedUpdates.then((_) => _appendTerminalOutput(job.id, safeLine));
    }

    final stdout = session.stdout
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(forward);
    final stderr = session.stderr
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(forward);
    await session.stdin.close();
    final exitCode = await session.waitForExit(timeout: timeout);
    if (exitCode == null && session.exitSignal == null) {
      session.kill(SSHSignal.TERM);
      session.close();
      await Future.wait<void>([stdout.cancel(), stderr.cancel()]);
      await _settleStreamedUpdates(streamedUpdates);
      await _appendTerminalOutput(
        job.id,
        '[client: command timed out after ${timeout.inSeconds}s]',
      );
      throw StateError(
        'The remote command timed out after ${timeout.inSeconds} seconds.',
      );
    }
    await _drainTranscriptStreams(stdout, stderr);
    session.close();
    await _settleStreamedUpdates(streamedUpdates);
    final combined = Uint8List.fromList(utf8.encode(outputLines.join('\n')));
    final resolvedExitCode = exitCode ?? 1;
    if (resolvedExitCode != 0) {
      await _appendTerminalOutput(
        job.id,
        '[client: command exited $resolvedExitCode]',
      );
    }
    return SSHRunResult(
      output: combined,
      exitCode: resolvedExitCode,
      stdout: combined,
      stderr: Uint8List(0),
      exitSignal: session.exitSignal,
    );
  }

  static List<String> _replaceRemoteInstallOutput(
    List<String> existing,
    List<String> remoteLines,
  ) {
    const marker = '[client: remote install output]';
    final markerIndex = existing.indexOf(marker);
    final bootstrapAndCommands = markerIndex == -1
        ? List<String>.of(existing)
        : existing.sublist(0, markerIndex);
    if (remoteLines.isEmpty) {
      return _boundedTerminalOutput(bootstrapAndCommands);
    }
    return _boundedTerminalOutput([
      ...bootstrapAndCommands,
      marker,
      ...remoteLines,
    ]);
  }

  static String? _bootstrapTranscriptLine(
    String line, {
    required String rootPassword,
    required String rootPrivateKey,
  }) {
    if (line.startsWith('NMTK_SETUP_PHASE|') ||
        line.startsWith('NMTK_SETUP_STEP|') ||
        line.startsWith('NMTK_SETUP_DONE|') ||
        line.startsWith('NMTK_SETUP_ERROR|') ||
        line.startsWith('NMTK_SETUP_TERMINAL|') ||
        line.startsWith('NMTK_DEPLOY_PRIVATE_KEY_B64=')) {
      return null;
    }
    final commandMarker =
        RegExp(r'^NMTK_SETUP_COMMAND\|(.*)$').firstMatch(line);
    final commandExitMarker =
        RegExp(r'^NMTK_SETUP_COMMAND_EXIT\|([^|]+)\|(.+)$').firstMatch(line);
    final transcriptLine = commandMarker != null
        ? '\$ ${commandMarker.group(1) ?? ''}'
        : commandExitMarker?.group(1) == 'timeout'
            ? '[client: command timed out after '
                '${commandExitMarker?.group(2)}s]'
            : commandExitMarker != null
                ? '[client: command exited ${commandExitMarker.group(2)}]'
                : line;
    return _redactBootstrapOutput(
      transcriptLine,
      rootPassword,
      rootPrivateKey,
    );
  }

  static ({
    String state,
    int timeoutSeconds,
    bool automaticRecovery,
    String label,
  })? _bootstrapOperationMarker(String line) {
    final marker = RegExp(
      r'^NMTK_SETUP_STEP\|(start|finish)\|(\d+)\|(true|false)\|([^|\r\n]+)$',
    ).firstMatch(line);
    final timeoutSeconds = int.tryParse(marker?.group(2) ?? '');
    if (marker == null || timeoutSeconds == null || timeoutSeconds <= 0) {
      return null;
    }
    return (
      state: marker.group(1)!,
      timeoutSeconds: timeoutSeconds,
      automaticRecovery: marker.group(3) == 'true',
      label: marker.group(4)!,
    );
  }

  @visibleForTesting
  static ({
    String state,
    int timeoutSeconds,
    bool automaticRecovery,
    String label,
  })? parseBootstrapOperationMarkerForTesting(String line) {
    return _bootstrapOperationMarker(line);
  }

  static DeploymentFailureDetails _administratorStepTimeoutDetails({
    required String label,
    required int timeoutSeconds,
    required String phase,
  }) {
    return DeploymentFailureDetails(
      code: 'administrator_step_timeout',
      phase: phase,
      summary: '$label timed out',
      recovery: 'The app stopped this server step automatically. '
          'Select Retry; if it times out again, open the raw SSH output to '
          'identify the server problem.',
      technicalDetails: '$label did not finish within its '
          '$timeoutSeconds-second command timeout and cleanup grace.',
      exitCode: 124,
    );
  }

  /// Reported when the server stops printing anything while no single command
  /// is nominally responsible — the gap that used to leave setup at the same
  /// percentage indefinitely.
  static DeploymentFailureDetails _administratorStallDetails({
    required String phase,
  }) {
    return DeploymentFailureDetails(
      code: 'administrator_stalled',
      phase: phase,
      summary: 'The server stopped reporting progress',
      recovery: 'The app stopped waiting automatically. Select Retry; if it '
          'stalls again, open the raw SSH output to see the last command the '
          'server ran.',
      technicalDetails: 'No server output arrived for '
          '$_bootstrapIdleTimeoutSeconds seconds while no command was active.',
      exitCode: 124,
    );
  }

  @visibleForTesting
  static DeploymentFailureDetails administratorStallForTesting({
    required String phase,
  }) {
    return _administratorStallDetails(phase: phase);
  }

  @visibleForTesting
  static DeploymentFailureDetails administratorStepTimeoutForTesting({
    required String label,
    required int timeoutSeconds,
    required String phase,
  }) {
    return _administratorStepTimeoutDetails(
      label: label,
      timeoutSeconds: timeoutSeconds,
      phase: phase,
    );
  }

  @visibleForTesting
  static String? parseBootstrapTranscriptLineForTesting(
    String line, {
    String rootPassword = '',
    String rootPrivateKey = '',
  }) =>
      _bootstrapTranscriptLine(
        line,
        rootPassword: rootPassword,
        rootPrivateKey: rootPrivateKey,
      );

  @visibleForTesting
  static List<String> boundTerminalOutputForTesting(List<String> lines) =>
      _boundedTerminalOutput(lines);

  @visibleForTesting
  static List<String> replaceRemoteInstallOutputForTesting(
    List<String> existing,
    List<String> remoteLines,
  ) =>
      _replaceRemoteInstallOutput(existing, remoteLines);

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
        'LAUNCHER_CONTROL_PORT': '$_launcherControlPort',
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
    if (current.stage == DeploymentPhase.cancelled.wireName) return;
    await _updateJob(
      current.copyWith(
        stage: phase.wireName,
        percent: percent,
        stageLabel: label,
        logs: [...current.logs, label],
        updatedAt: DateTime.now(),
        lastProgressAt: DateTime.now(),
      ),
    );
  }

  Future<void> _appendTerminalOutput(String jobId, String line) async {
    final current = _jobs[jobId];
    if (current == null ||
        current.stage == DeploymentPhase.cancelled.wireName) {
      return;
    }
    _jobs[jobId] = current.copyWith(
      terminalOutput: _boundedTerminalOutput([
        ...current.terminalOutput,
        _redactBootstrapOutput(line, '', ''),
      ]),
      updatedAt: DateTime.now(),
      lastProgressAt: DateTime.now(),
    );
    _terminalPersistenceTimers[jobId] ??= Timer(
      const Duration(milliseconds: 300),
      () {
        _terminalPersistenceTimers.remove(jobId);
        unawaited(_persistCurrentJob(jobId));
      },
    );
  }

  Future<void> _setActiveOperation(
    String jobId,
    DeploymentActiveOperation? operation,
  ) async {
    _operationHeartbeatTimers.remove(jobId)?.cancel();
    final current = _jobs[jobId];
    if (current == null ||
        current.stage == DeploymentPhase.cancelled.wireName) {
      return;
    }
    await _updateJob(
      current.copyWith(
        activeOperation: operation,
        clearActiveOperation: operation == null,
        updatedAt: DateTime.now(),
        lastProgressAt: DateTime.now(),
      ),
    );
    if (operation == null) return;
    _operationHeartbeatTimers[jobId] = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        final latest = _jobs[jobId];
        if (latest == null ||
            latest.isTerminal ||
            latest.activeOperation?.startedAt != operation.startedAt) {
          _operationHeartbeatTimers.remove(jobId)?.cancel();
          return;
        }
        unawaited(
          _updateJob(latest.copyWith(updatedAt: DateTime.now())),
        );
      },
    );
  }

  static List<String> _boundedTerminalOutput(List<String> lines) {
    const maxLines = 2000;
    const maxCharacters = 512000;
    const truncationMarker = '[client: earlier SSH output truncated]';
    final alreadyTruncated = lines.contains(truncationMarker);
    final source = lines.where((line) => line != truncationMarker).toList();
    var truncated = alreadyTruncated || source.length > maxLines;
    final bounded = source.length > maxLines
        ? source.sublist(source.length - maxLines)
        : List<String>.of(source);
    var characters = bounded.fold<int>(
      0,
      (total, line) => total + line.length + 1,
    );
    while (bounded.isNotEmpty && characters > maxCharacters) {
      characters -= bounded.removeAt(0).length + 1;
      truncated = true;
    }
    if (truncated) {
      while (bounded.length >= maxLines) {
        bounded.removeAt(0);
      }
      while (bounded.isNotEmpty &&
          characters + truncationMarker.length + 1 > maxCharacters) {
        characters -= bounded.removeAt(0).length + 1;
      }
      bounded.insert(0, truncationMarker);
    }
    return List<String>.unmodifiable(bounded);
  }

  Future<DeploymentJob> _updateJob(DeploymentJob job) async {
    if (job.isTerminal) {
      _operationHeartbeatTimers.remove(job.id)?.cancel();
      if (job.activeOperation != null) {
        job = job.copyWith(clearActiveOperation: true);
      }
    }
    _terminalPersistenceTimers.remove(job.id)?.cancel();
    _jobs[job.id] = job;
    await (await _store).saveActiveJob(job);
    return job;
  }

  Future<void> _persistCurrentJob(String jobId) async {
    final current = _jobs[jobId];
    if (current != null) {
      await (await _store).saveActiveJob(current);
    }
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
    return _redactBootstrapOutput(result, '', '');
  }

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";

  @visibleForTesting
  static String administratorShellCommand({required bool needsSudo}) =>
      needsSudo ? 'sudo -S -p "" bash' : 'bash';
}

class _AdministratorOperation {
  const _AdministratorOperation(this.client, this.session);

  final SSHClient client;
  final SSHSession session;
}

class _AdministratorSessionExit {
  const _AdministratorSessionExit(this.exitCode);

  final int? exitCode;
}

class _RemoteSetupException implements Exception {
  const _RemoteSetupException(this.details);

  final DeploymentFailureDetails details;

  @override
  String toString() => details.summary;
}
