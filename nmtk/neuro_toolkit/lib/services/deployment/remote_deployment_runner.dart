import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/bootstrap_transcript_parsing.dart';
import 'package:neuro_toolkit/services/deployment/deployment_asset_bundle.dart';
import 'package:neuro_toolkit/services/deployment/deployment_persistence.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/job_registry.dart';
import 'package:neuro_toolkit/services/deployment/ssh_deployment_service.dart';
import 'package:path/path.dart' as path;

/// Builds the argv list passed to `install.sh` on the remote host.
List<String> buildRemoteInstallCommandArgs({
  required String containerEngine,
  required int backendPort,
  required String imageTag,
  required bool cleanInstall,
  required String host,
  required String statusFile,
  required String logFile,
  bool schemaMigration = false,
}) {
  final args = <String>[
    'bash',
    'install.sh',
    containerEngine,
    backendPort.toString(),
    imageTag,
    cleanInstall.toString(),
    host,
    statusFile,
    logFile,
  ];
  if (schemaMigration) {
    args.addAll(const ['--schema-migration', 'true']);
  }
  return args;
}

/// Runs SSH-based deployment work against a remote host that is already
/// reachable: starting the detached install, polling its progress, and
/// uploading or verifying the deployment bundle. Provisioning a brand-new
/// host's administrator account is [RemoteServerProvisioner]'s job, not
/// this class's.
class RemoteDeploymentRunner {
  const RemoteDeploymentRunner({
    SshDeploymentService ssh = const SshDeploymentService(),
  }) : _ssh = ssh;

  final SshDeploymentService _ssh;

  /// Upper bound on one status-file read. Without it a wedged SSH read stops
  /// every later poll, because the notifier drops overlapping ticks.
  static const Duration _statusPollTimeout = Duration(seconds: 20);

  Future<SSHClient> connect(
    DeploymentRequest request,
    DeploymentPersistence persistence,
  ) {
    return _ssh.connect(request: request, persistence: persistence);
  }

  Future<void> startRemoteDeployment(
    DeploymentJob job,
    DeploymentTarget target,
    DeploymentRequest request,
    DeploymentAssetBundle bundle, {
    required JobRegistry registry,
    required AssetBundle assets,
  }) async {
    final progressFloor = registry.jobs[job.id]?.percent ?? 0;
    await registry.emit(
      job,
      DeploymentPhase.connecting,
      progressFloor > 5 ? progressFloor : 5,
      'Connecting with SSH',
    );
    final client = await connect(request, await registry.store);
    try {
      await registry.emit(
        job,
        DeploymentPhase.installingPrerequisites,
        progressFloor > 12 ? progressFloor : 12,
        'Preparing ${request.containerEngine}',
      );
      await _ensureRemoteEngine(client, request, job, registry);
      final deployDir = await remoteDeployDir(
        client,
        registry: registry,
        job: job,
        request: request,
      );
      final jobDir = '$deployDir/.jobs';
      await runChecked(
        client,
        'mkdir -p ${shellQuote(deployDir)} ${shellQuote(jobDir)}',
        'Could not create the deployment directory.',
        registry: registry,
        job: job,
        request: request,
      );
      await registry.emit(
        job,
        DeploymentPhase.uploadingAssets,
        25,
        'Uploading deployment bundle v${bundle.version} '
        '(${_shortHash(bundle.manifestHash)})',
      );
      await _uploadAssets(
        client,
        deployDir,
        assets: assets,
        registry: registry,
        job: job,
        request: request,
      );
      await _verifyRemoteAssets(
        client,
        deployDir,
        bundle,
        registry: registry,
        job: job,
        request: request,
      );
      await _syncRemoteDotenv(client, deployDir, request);
      await registry.emit(
        job,
        DeploymentPhase.uploadingAssets,
        30,
        'Verified deployment bundle v${bundle.version} '
        '(${_shortHash(bundle.manifestHash)})',
      );
      final status = '$jobDir/${job.id}.status';
      final log = '$jobDir/${job.id}.log';
      final pid = '$jobDir/${job.id}.pid';
      final installCommand = buildRemoteInstallCommandArgs(
        containerEngine: request.containerEngine,
        backendPort: request.backendPort,
        imageTag: request.deploymentImageTag,
        cleanInstall: request.cleanInstall,
        host: request.host,
        statusFile: status,
        logFile: log,
        schemaMigration: request.schemaMigration,
      ).map(shellQuote).join(' ');
      // ponytail: `sg` is absent on Ubuntu 26.04 and the SSH login already has
      // the docker group, so only re-enter the group when `sg` actually exists.
      final detachedCommand = request.containerEngine == 'docker'
          ? 'if command -v sg >/dev/null 2>&1; then '
                'sg docker -c ${shellQuote(installCommand)}; '
                'else $installCommand; fi'
          : installCommand;
      final command =
          'cd ${shellQuote(deployDir)} && chmod 700 install.sh && '
          'nohup sh -c ${shellQuote(detachedCommand)} </dev/null '
          '>/dev/null 2>&1 & echo \$! > ${shellQuote(pid)}';
      await runChecked(
        client,
        command,
        'Could not start the detached deployment job.',
        registry: registry,
        job: job,
        request: request,
      );
    } finally {
      client.close();
    }
  }

  Future<DeploymentJob> pollRemoteJob(
    DeploymentJob job,
    DeploymentTarget target,
    DeploymentRequest request, {
    required JobRegistry registry,
    required Future<DeploymentJob> Function(
      DeploymentJob job,
      DeploymentTarget target, {
      String? hostOverride,
    })
    verifyRemoteApis,
    required DeploymentJob Function(
      DeploymentJob job,
      DeploymentTarget target, {
      Object? cause,
    })
    clientReachabilityFailure,
  }) async {
    final client = await connect(request, await registry.store);
    try {
      final deployDir = await remoteDeployDir(client);
      final jobDir = '$deployDir/.jobs';
      final result = await client
          .runWithResult(
            'cat ${shellQuote('$jobDir/${job.id}.status')} 2>/dev/null; '
            'printf "\\n---NMTK-LOG---\\n"; '
            'tail -c 512000 ${shellQuote('$jobDir/${job.id}.log')} 2>/dev/null',
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
      final terminalOutput = replaceRemoteInstallOutput(
        job.terminalOutput,
        remoteLogLines,
      );
      // Only real movement may refresh the progress clock. Stamping it on every
      // poll made the notifier's staleness watchdog unreachable, which is how a
      // dead deployment could keep looking alive indefinitely.
      final reportedProgress =
          stage != job.stage ||
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
      // The install itself finishing is what makes the credential real: the
      // deploy key and admin token in `request` are the ones the backend now
      // running on the server actually uses. Persisting only after
      // verification passed meant a failed verification threw them away and
      // orphaned a working backend, leaving reinstall as the only route back.
      if (stage == DeploymentPhase.completed.wireName &&
          registry.pendingRequests.containsKey(job.id)) {
        await (await registry.store).saveTarget(target, request);
        registry.pendingTargets.remove(job.id);
        registry.pendingRequests.remove(job.id);
      }
      if (stage == DeploymentPhase.completed.wireName) {
        try {
          next = await verifyRemoteApis(next, target);
        } catch (error) {
          // Swallowing this reported "the server is unreachable" for causes
          // that had nothing to do with the network — a rejected token, a
          // module that would not start — and left no way to tell them apart.
          next = clientReachabilityFailure(next, target, cause: error);
        }
      }
      if (next.isTerminal) {
        registry.pendingTargets.remove(job.id);
        registry.pendingRequests.remove(job.id);
      }
      return registry.updateJob(next);
    } finally {
      client.close();
    }
  }

  Future<String> remoteDeployDir(
    SSHClient client, {
    JobRegistry? registry,
    DeploymentJob? job,
    DeploymentRequest? request,
    bool requireDeploymentAccount = true,
  }) async {
    final result = job != null && request != null && registry != null
        ? await _runRemoteCommand(
            client,
            'printf %s "\$HOME"',
            registry: registry,
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
    // The backend lives in the deployment account's home and in that
    // account's container store. Operating from any other login silently
    // builds a second, parallel stack there, which then fails to start
    // because the real one already holds the published ports — reported as
    // "the server could not restart the NMTK backend" with nothing pointing
    // at the actual cause.
    if (!requireDeploymentAccount) return '$home/.nmtk/deploy';
    final owner = utf8
        .decode(
          (await client.runWithResult(
            'getent passwd nmtk-deploy 2>/dev/null | cut -d: -f6',
          )).stdout,
        )
        .trim();
    if (owner.isNotEmpty && owner != home) {
      throw StateError(
        'This server\'s backend belongs to the nmtk-deploy account, but the '
        'saved credential signs in as a different user. Reinstall from '
        'Backend Setup to re-link the deployment account.',
      );
    }
    return '$home/.nmtk/deploy';
  }

  /// Recovers the administrator token from a backend that is already
  /// installed and running, so linking credentials can reconnect to it
  /// instead of insisting on a reinstall the user does not need.
  ///
  /// A returned token is one the live launcher control has just accepted, so
  /// a stale copy left behind by an abandoned install is never mistaken for
  /// the running stack's.
  Future<String> readExistingAdminToken(
    DeploymentRequest request,
    DeploymentPersistence persistence,
  ) async {
    try {
      final client = await connect(request, persistence);
      try {
        final deployDir = await remoteDeployDir(
          client,
          // Deliberately the login account's own copy: this probe exists to
          // find a token when the deployment account is not reachable yet.
          requireDeploymentAccount: false,
        );
        final script = buildAdminTokenProbeScript(
          loginDeployDir: deployDir,
          backendPort: request.backendPort,
        );
        final direct = await client
            .runWithResult(script)
            .timeout(_statusPollTimeout);
        final token = _parseProbedAdminToken(utf8.decode(direct.stdout));
        if (token.isNotEmpty) return token;
        // Try passwordless sudo first (covers NOPASSWD rules and sudo-rs on
        // Ubuntu 26.04 where the admin account has key-only SSH + sudo access).
        try {
          final nopassSession = await client.execute('sudo -n bash');
          nopassSession.stdin.add(Uint8List.fromList(utf8.encode(script)));
          await nopassSession.stdin.close();
          final nopassOut = await nopassSession.stdout
              .cast<List<int>>()
              .transform(utf8.decoder)
              .join()
              .timeout(_statusPollTimeout);
          final nopassToken = _parseProbedAdminToken(nopassOut);
          if (nopassToken.isNotEmpty) return nopassToken;
        } on Object {
          // NOPASSWD sudo not available; fall through to password path.
        }
        // Password-based sudo: only possible when the SSH password is known.
        if (request.sshPassword.isEmpty) return '';
        final session = await client.execute('sudo -S -p "" bash');
        session.stdin.add(
          Uint8List.fromList(utf8.encode('${request.sshPassword}\n$script')),
        );
        await session.stdin.close();
        final elevated = await session.stdout
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join()
            .timeout(_statusPollTimeout);
        return _parseProbedAdminToken(elevated);
      } finally {
        client.close();
      }
    } on Object {
      // Unreachable host, refused credential, or no running backend: the
      // caller falls back to the reinstall path and reports that failure.
      return '';
    }
  }

  String _parseProbedAdminToken(String output) {
    for (final line in const LineSplitter().convert(output)) {
      if (line.startsWith('NMTK_ADMIN_TOKEN|')) {
        return line.substring('NMTK_ADMIN_TOKEN|'.length).trim();
      }
    }
    return '';
  }

  Future<void> uploadAssetsForRepair(
    SSHClient client,
    String deployDir, {
    required AssetBundle assets,
  }) async {
    final sftp = await client.sftp();
    for (final relative in DeploymentAssetBundle.assetFiles) {
      final parent = path.posix.dirname(relative);
      if (parent != '.') {
        final result = await client.runWithResult(
          'mkdir -p ${shellQuote(path.posix.join(deployDir, parent))}',
        );
        if (result.exitCode != 0) {
          throw StateError('Could not prepare the backend repair directory.');
        }
      }
      final data = await assets.load('assets/deployment/$relative');
      final remote = await sftp.open(
        path.posix.join(deployDir, relative),
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate |
            SftpFileOpenMode.write,
      );
      try {
        await remote.writeBytes(DeploymentAssetBundle.exactBytes(data));
      } finally {
        await remote.close();
      }
    }
  }

  Future<void> runChecked(
    SSHClient client,
    String command,
    String failureMessage, {
    JobRegistry? registry,
    DeploymentJob? job,
    DeploymentRequest? request,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final result = job != null && request != null && registry != null
        ? await _runRemoteCommand(
            client,
            command,
            registry: registry,
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

  Future<void> _ensureRemoteEngine(
    SSHClient client,
    DeploymentRequest request,
    DeploymentJob job,
    JobRegistry registry,
  ) async {
    final engine = request.containerEngine;
    final install = engine == 'podman'
        ? 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive '
              'apt-get install -y -qq podman podman-compose'
        : 'curl -fsSL https://get.docker.com | sh';
    final elevated = request.sshPassword.isNotEmpty
        ? 'printf %s\\\\n ${shellQuote(request.sshPassword)} | '
              'sudo -S -p "" sh -c ${shellQuote(install)}'
        : 'sudo -n sh -c ${shellQuote(install)}';
    await runChecked(
      client,
      'command -v ${shellQuote(engine)} >/dev/null 2>&1 || $elevated',
      'Could not install $engine. Use an administrator account or configure '
          'passwordless sudo, then retry.',
      registry: registry,
      job: job,
      request: request,
    );
    if (engine == 'docker') {
      final addGroup = request.sshPassword.isNotEmpty
          ? 'printf %s\\\\n ${shellQuote(request.sshPassword)} | '
                'sudo -S -p "" usermod -aG docker "\$USER"'
          : 'sudo -n usermod -aG docker "\$USER"';
      await runChecked(
        client,
        'docker ps >/dev/null 2>&1 || $addGroup',
        'Docker is installed, but this SSH account cannot use it.',
        registry: registry,
        job: job,
        request: request,
      );
    } else {
      await runChecked(
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
        registry: registry,
        job: job,
        request: request,
      );
    }
  }

  Future<void> _uploadAssets(
    SSHClient client,
    String deployDir, {
    required AssetBundle assets,
    required JobRegistry registry,
    required DeploymentJob job,
    required DeploymentRequest request,
  }) async {
    final sftp = await client.sftp();
    for (final relative in DeploymentAssetBundle.assetFiles) {
      final parent = path.posix.dirname(relative);
      if (parent != '.') {
        await runChecked(
          client,
          'mkdir -p ${shellQuote(path.posix.join(deployDir, parent))}',
          'Could not create a remote deployment directory.',
          registry: registry,
          job: job,
          request: request,
        );
      }
      final data = await assets.load('assets/deployment/$relative');
      final remote = await sftp.open(
        path.posix.join(deployDir, relative),
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate |
            SftpFileOpenMode.write,
      );
      try {
        await remote.writeBytes(DeploymentAssetBundle.exactBytes(data));
      } finally {
        await remote.close();
      }
    }
    if (request.adminToken.isNotEmpty) {
      final credentialsDir = path.posix.join(deployDir, 'credentials');
      await runChecked(
        client,
        'mkdir -p ${shellQuote(credentialsDir)}',
        'Could not prepare deployment credentials.',
        registry: registry,
        job: job,
        request: request,
      );
      final remote = await sftp.open(
        path.posix.join(credentialsDir, 'admin-token'),
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate |
            SftpFileOpenMode.write,
      );
      try {
        await remote.writeBytes(
          Uint8List.fromList(utf8.encode(request.adminToken)),
        );
      } finally {
        await remote.close();
      }
      await runChecked(
        client,
        'chmod 750 ${shellQuote(credentialsDir)} && '
            'chmod 640 ${shellQuote(path.posix.join(credentialsDir, 'admin-token'))}',
        'Could not protect deployment credentials.',
        registry: registry,
        job: job,
        request: request,
      );
    }
  }

  Future<void> _verifyRemoteAssets(
    SSHClient client,
    String deployDir,
    DeploymentAssetBundle bundle, {
    required JobRegistry registry,
    required DeploymentJob job,
    required DeploymentRequest request,
  }) async {
    final files = <String>[
      ...bundle.fileHashes.keys,
      'deployment-manifest.json',
    ];
    final result = await _runRemoteCommand(
      client,
      'cd ${shellQuote(deployDir)} && sha256sum '
      '${files.map(shellQuote).join(' ')}',
      registry: registry,
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

  Future<SSHRunResult> _runRemoteCommand(
    SSHClient client,
    String command, {
    required JobRegistry registry,
    required DeploymentJob job,
    required DeploymentRequest request,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    await registry.appendTerminalOutput(
      job.id,
      '\$ ${redactForLogging(command, request)}',
    );
    final session = await client.execute('sh -c ${shellQuote(command)} 2>&1');
    final outputLines = <String>[];
    var streamedUpdates = Future<void>.value();

    void forward(String line) {
      outputLines.add(line);
      final safeLine = redactForLogging(line, request);
      streamedUpdates = streamedUpdates.then(
        (_) => registry.appendTerminalOutput(job.id, safeLine),
      );
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
      await settleStreamedUpdates(streamedUpdates);
      await registry.appendTerminalOutput(
        job.id,
        '[client: command timed out after ${timeout.inSeconds}s]',
      );
      throw StateError(
        'The remote command timed out after ${timeout.inSeconds} seconds.',
      );
    }
    await drainTranscriptStreams(stdout, stderr);
    session.close();
    await settleStreamedUpdates(streamedUpdates);
    final combined = Uint8List.fromList(utf8.encode(outputLines.join('\n')));
    final resolvedExitCode = exitCode ?? 1;
    if (resolvedExitCode != 0) {
      await registry.appendTerminalOutput(
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

  static String _shortHash(String hash) =>
      hash.length <= 12 ? hash : hash.substring(0, 12);

  Future<void> _syncRemoteDotenv(
    SSHClient client,
    String deployDir,
    DeploymentRequest request,
  ) async {
    final values = <String, String>{
      ...request.moduleEnvironment,
      ...request.moduleSecrets,
    };
    if (values.isEmpty) return;
    final payload = jsonEncode(values);
    final script =
        "python3 - <<'PY'\n"
        'import json, pathlib\n'
        'deploy = pathlib.Path(${jsonEncode(deployDir)})\n'
        'path = deploy / ".env"\n'
        'path.parent.mkdir(parents=True, exist_ok=True)\n'
        'values = json.loads(${jsonEncode(payload)})\n'
        'existing = {}\n'
        'if path.exists():\n'
        '    for line in path.read_text(encoding="utf-8").splitlines():\n'
        '        if not line or line.startswith("#") or "=" not in line:\n'
        '            continue\n'
        '        key, value = line.split("=", 1)\n'
        '        existing[key.strip()] = value\n'
        'existing.update(values)\n'
        'path.write_text("\\n".join(f"{k}={v}" for k, v in sorted(existing.items())) + "\\n", encoding="utf-8")\n'
        'PY';
    await runChecked(
      client,
      'cd ${shellQuote(deployDir)} && $script',
      'Could not write module configuration to the server.',
    );
  }
}

/// Prints `NMTK_ADMIN_TOKEN|<token>` for the first candidate file the running
/// backend authenticates with. The released stack runs as the isolated
/// nmtk-deploy account, so its copy is tried first when the login account is a
/// different one.
///
/// Probes suite_api rather than launcher control: launcher control runs as a
/// non-root container user and cannot read the compose secret at all, so it
/// answers 401 even to a correct token. Anything other than 401/403 means the
/// token authenticated — a valid token on a route that is not mounted returns
/// 404, which still proves the credential.
String buildAdminTokenProbeScript({
  required String loginDeployDir,
  required int backendPort,
}) =>
    '''
set -- ${shellQuote('$loginDeployDir/credentials/admin-token')}
nmtk_deploy_home=\$(getent passwd nmtk-deploy 2>/dev/null | cut -d: -f6)
if [ -n "\$nmtk_deploy_home" ]; then
  set -- "\$nmtk_deploy_home/.nmtk/deploy/credentials/admin-token" "\$@"
fi
for nmtk_token_file in "\$@"; do
  nmtk_token=\$(cat "\$nmtk_token_file" 2>/dev/null) || continue
  [ -n "\$nmtk_token" ] || continue
  nmtk_code=\$(curl -s -o /dev/null -m 5 -w '%{http_code}' \\
    -H "X-NMTK-Admin-Token: \$nmtk_token" \\
    "http://127.0.0.1:$backendPort/api/neurocnl/health" 2>/dev/null)
  case "\$nmtk_code" in
    ''|000|401|403) continue ;;
  esac
  printf 'NMTK_ADMIN_TOKEN|%s\\n' "\$nmtk_token"
  exit 0
done
exit 1
''';
