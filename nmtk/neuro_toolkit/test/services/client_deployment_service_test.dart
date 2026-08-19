import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/client_deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/deployment_persistence.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/ssh_deployment_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecretStorage implements DeploymentSecretStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class _ManifestAssetBundle extends CachingAssetBundle {
  _ManifestAssetBundle({
    this.corruptedFile,
    this.omittedManifestFile,
    this.unexpectedManifestFile,
    this.useOffsetByteData = false,
  });

  final String? corruptedFile;
  final String? omittedManifestFile;
  final String? unexpectedManifestFile;
  final bool useOffsetByteData;

  static const files = <String>[
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

  static List<int> _fileBytes(String relative) =>
      utf8.encode('fixture contents for $relative\n');

  ByteData _byteData(List<int> bytes) {
    final exact = Uint8List.fromList(bytes);
    if (!useOffsetByteData) return ByteData.sublistView(exact);
    final padded = Uint8List(exact.length + 7);
    padded.setRange(3, 3 + exact.length, exact);
    return ByteData.view(padded.buffer, 3, exact.length);
  }

  @override
  Future<ByteData> load(String key) async {
    const prefix = 'assets/deployment/';
    if (!key.startsWith(prefix)) {
      throw StateError('Unexpected fixture asset: $key');
    }
    final relative = key.substring(prefix.length);
    if (relative == 'deployment-manifest.json') {
      final hashes = <String, String>{
        for (final file in files)
          file: sha256.convert(_fileBytes(file)).toString(),
      };
      if (omittedManifestFile != null) {
        hashes.remove(omittedManifestFile);
      }
      if (unexpectedManifestFile != null) {
        hashes[unexpectedManifestFile!] =
            sha256.convert(utf8.encode('unexpected fixture')).toString();
      }
      return _byteData(
        utf8.encode(
          jsonEncode({
            'bundleVersion': 5,
            'files': hashes,
          }),
        ),
      );
    }
    if (!files.contains(relative)) {
      throw StateError('Unexpected fixture asset: $key');
    }
    final bytes = relative == corruptedFile
        ? utf8.encode('corrupted fixture contents for $relative\n')
        : _fileBytes(relative);
    return _byteData(bytes);
  }
}

class _BlockingSshDeploymentService extends SshDeploymentService {
  _BlockingSshDeploymentService();

  @override
  Future<SSHClient> connect({
    required DeploymentRequest request,
    required DeploymentPersistence persistence,
  }) {
    return Completer<SSHClient>().future;
  }
}

void _writeExecutable(Directory bin, String name, String contents) {
  final file = File('${bin.path}/$name')..writeAsStringSync(contents);
  final chmod = Process.runSync('chmod', ['+x', file.path]);
  if (chmod.exitCode != 0) {
    throw StateError('Could not prepare fake $name command: ${chmod.stderr}');
  }
}

({
  ProcessResult result,
  String commandLog,
  String dormantUser,
  String skippedUser,
}) _runRootlessReconciliationFixture({
  bool unsafeActiveRuntime = false,
  bool failRuntimeCleanup = false,
  bool factoryReset = false,
  bool requireRootWorkingDirectory = false,
  int candidateInfoExit = 0,
  int rootInfoExit = 0,
  String discoveredContainerOutput = '',
  String discoveredVolumeOutput = '',
}) {
  final fixture = Directory.systemTemp.createTempSync(
    'nmtk-rootless-reconcile-',
  );
  final bin = Directory('${fixture.path}/bin')..createSync();
  final runtimeBase = Directory('${fixture.path}/run-user')..createSync();
  final dormantHome = Directory('${fixture.path}/dormant-home')
    ..createSync(recursive: true);
  Directory('${dormantHome.path}/.local/share/containers/storage')
      .createSync(recursive: true);
  final skippedHome = Directory('${fixture.path}/skipped-home')..createSync();
  const dormantUser = 'dormant-nmtk';
  const skippedUser = 'unrelated-user';
  const dormantUid = 48331;
  const dormantGid = 48331;
  final passwd = File('${fixture.path}/passwd')
    ..writeAsStringSync(
      '$dormantUser:x:$dormantUid:$dormantGid::${dormantHome.path}:/bin/bash\n'
      '$skippedUser:x:48332:48332::${skippedHome.path}:/bin/bash\n',
    );
  final commandLog = File('${fixture.path}/commands.log');
  if (unsafeActiveRuntime) {
    Directory('${runtimeBase.path}/$dormantUid/libpod')
        .createSync(recursive: true);
  }

  _writeExecutable(bin, 'id', '#!/bin/bash\necho 0\n');
  _writeExecutable(bin, 'uname', '#!/bin/bash\necho Linux\n');
  _writeExecutable(
    bin,
    'df',
    '#!/bin/bash\n'
        "printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\n'\n"
        "printf '/dev/fake 20000000 1 19999999 1%% /\\n'\n",
  );
  _writeExecutable(
    bin,
    'timeout',
    '#!/bin/bash\n'
        'while [[ "\$1" == --* ]]; do shift; done\n'
        'shift\n'
        'exec "\$@"\n',
  );
  _writeExecutable(
    bin,
    'podman',
    '#!/bin/bash\n'
        'printf "podman HOME=%s XDG_RUNTIME_DIR=%s args=%s\\n" '
        '"\${HOME:-}" "\${XDG_RUNTIME_DIR:-}" "\$*" >>"\$NMTK_FAKE_LOG"\n'
        'case "\$*" in\n'
        '  "ps -a --format "*|"ps -aq --filter "*)\n'
        '    printf \'time="2026-07-29T00:00:00Z" level=warning msg="fixture warning"\\n\' >&2\n'
        '    ;;\n'
        'esac\n'
        'if [[ "\$*" == info* ]]; then\n'
        '  if [[ -n "\${NMTK_FAKE_VIA_RUNUSER:-}" ]]; then\n'
        '    exit $candidateInfoExit\n'
        '  fi\n'
        '  exit $rootInfoExit\n'
        'fi\n'
        'if [[ "\$*" == "ps -aq --filter label=com.docker.compose.project=nmtk" ]]; then\n'
        "  printf '%s\\n' ${jsonEncode(discoveredContainerOutput)}\n"
        'fi\n'
        'if [[ "\$*" == "volume ls -q --filter label=com.docker.compose.project=nmtk" ]]; then\n'
        "  printf '%s\\n' ${jsonEncode(discoveredVolumeOutput)}\n"
        'fi\n',
  );
  _writeExecutable(
    bin,
    'runuser',
    '#!/bin/bash\n'
        'printf "runuser %s\\n" "\$*" >>"\$NMTK_FAKE_LOG"\n'
        // Real runuser refuses before it execs anything when the inherited
        // directory is one the target account may not enter.
        'if [[ -n "\${NMTK_FAKE_REQUIRE_ROOT_CWD:-}" && "\$PWD" != "/" ]]; then\n'
        '  printf "cannot chdir to %s: Permission denied\\n" "\$PWD" >&2\n'
        '  exit 1\n'
        'fi\n'
        'while [[ "\$1" != "--" ]]; do shift; done\n'
        'shift\n'
        'export NMTK_FAKE_VIA_RUNUSER=1\n'
        'exec "\$@"\n',
  );
  _writeExecutable(
    bin,
    'chown',
    '#!/bin/bash\n'
        'printf "chown %s\\n" "\$*" >>"\$NMTK_FAKE_LOG"\n',
  );
  _writeExecutable(
    bin,
    'stat',
    '#!/bin/bash\n'
        'echo ${unsafeActiveRuntime ? 99999 : dormantUid}\n',
  );
  if (failRuntimeCleanup) {
    _writeExecutable(
      bin,
      'rm',
      '#!/bin/bash\n'
          'for argument in "\$@"; do\n'
          '  case "\$argument" in\n'
          '    /tmp/nmtk-podman-runtime.*)\n'
          '      printf "rm-failed %s\\n" "\$argument" >>"\$NMTK_FAKE_LOG"\n'
          '      exit 77\n'
          '      ;;\n'
          '  esac\n'
          'done\n'
          'exec /bin/rm "\$@"\n',
    );
  }

  final completeScript = ClientDeploymentService.buildRemoteBootstrapScript(
    containerEngine: 'podman',
    factoryReset: factoryReset,
  ).replaceFirst(
    'done </etc/passwd',
    'done <"${passwd.path}"',
  );
  final installPhase = completeScript.indexOf(
    '\nphase "installing_prerequisites"',
  );
  final reconciliationScript = '${completeScript.substring(0, installPhase)}\n'
      'terminal "✓ Reconciliation fixture completed"\n';
  final script = File('${fixture.path}/reconcile.sh')
    ..writeAsStringSync(reconciliationScript);
  final result = Process.runSync(
    'bash',
    [script.path],
    environment: {
      ...Platform.environment,
      'PATH': '${bin.path}:/usr/bin:/bin',
      'NMTK_FAKE_LOG': commandLog.path,
      'NMTK_SETUP_RUNTIME_BASE': runtimeBase.path,
      if (requireRootWorkingDirectory) 'NMTK_FAKE_REQUIRE_ROOT_CWD': '1',
    },
    // Deliberately not "/": the real setup session starts in the
    // administrator's home directory, which is what broke privilege drops.
    workingDirectory: fixture.path,
  );
  final log = commandLog.existsSync() ? commandLog.readAsStringSync() : '';
  if (failRuntimeCleanup) {
    final runtimeMatch = RegExp(
      r'XDG_RUNTIME_DIR=(/tmp/nmtk-podman-runtime\.[^\s]+)',
    ).firstMatch(log);
    final runtimePath = runtimeMatch?.group(1);
    if (runtimePath != null && Directory(runtimePath).existsSync()) {
      Directory(runtimePath).deleteSync(recursive: true);
    }
  }
  fixture.deleteSync(recursive: true);
  return (
    result: result,
    commandLog: log,
    dormantUser: dormantUser,
    skippedUser: skippedUser,
  );
}

({
  Directory fixture,
  List<ProcessResult> results,
  String commandLog,
}) _runDeploymentAccountFixture({
  required bool userExists,
  required bool groupExists,
  int runs = 1,
  bool failGroupCreation = false,
  bool invalidHome = false,
}) {
  final fixture = Directory.systemTemp.createTempSync(
    'nmtk-deployment-account-',
  );
  final bin = Directory('${fixture.path}/bin')..createSync();
  final deployHome = Directory('${fixture.path}/deploy-home');
  final userState = File('${fixture.path}/user-exists');
  final groupState = File('${fixture.path}/group-exists');
  final commandLog = File('${fixture.path}/commands.log');
  if (userExists) {
    userState.writeAsStringSync('present');
    deployHome.createSync();
  }
  if (groupExists) groupState.writeAsStringSync('present');

  _writeExecutable(
    bin,
    'timeout',
    '#!/bin/bash\n'
        'while [[ "\$1" == --* ]]; do shift; done\n'
        'shift\n'
        'exec "\$@"\n',
  );
  _writeExecutable(
    bin,
    'getent',
    '#!/bin/bash\n'
        'case "\$1:\$2" in\n'
        '  group:nmtk-deploy)\n'
        '    [[ -f "\$NMTK_GROUP_STATE" ]] || exit 2\n'
        '    printf "nmtk-deploy:x:48333:\\n"\n'
        '    ;;\n'
        '  passwd:nmtk-deploy)\n'
        '    [[ -f "\$NMTK_USER_STATE" ]] || exit 2\n'
        '    printf "nmtk-deploy:x:48333:48333::%s:/bin/bash\\n" '
        '"\$NMTK_DEPLOY_HOME"\n'
        '    ;;\n'
        '  *) exit 2 ;;\n'
        'esac\n',
  );
  _writeExecutable(
    bin,
    'id',
    '#!/bin/bash\n'
        'if [[ "\$1" == "-u" && \$# -eq 1 ]]; then echo 0; exit 0; fi\n'
        '[[ "\${!#}" == "nmtk-deploy" && '
        '-f "\$NMTK_USER_STATE" ]] || exit 1\n'
        '[[ "\$1" == "-u" ]] && echo 48333\n'
        'exit 0\n',
  );
  _writeExecutable(
    bin,
    'groupadd',
    '#!/bin/bash\n'
        'printf "groupadd %s\\n" "\$*" >>"\$NMTK_FAKE_LOG"\n'
        'if [[ "\$NMTK_FAIL_GROUP_CREATION" == "true" ]]; then\n'
        '  printf "password=%s account database locked\\n" '
        '"\$NMTK_FAKE_SECRET" >&2\n'
        '  exit 10\n'
        'fi\n'
        '[[ "\$1" == "nmtk-deploy" ]] || exit 64\n'
        '[[ ! -f "\$NMTK_GROUP_STATE" ]] || exit 9\n'
        'touch "\$NMTK_GROUP_STATE"\n',
  );
  _writeExecutable(
    bin,
    'useradd',
    '#!/bin/bash\n'
        'printf "useradd %s\\n" "\$*" >>"\$NMTK_FAKE_LOG"\n'
        '[[ -f "\$NMTK_GROUP_STATE" ]] || exit 6\n'
        '[[ ! -f "\$NMTK_USER_STATE" ]] || exit 9\n'
        '[[ " \$* " == *" --gid nmtk-deploy "* ]] || exit 65\n'
        'touch "\$NMTK_USER_STATE"\n'
        'mkdir -p "\$NMTK_DEPLOY_HOME"\n',
  );
  _writeExecutable(
    bin,
    'usermod',
    '#!/bin/bash\n'
        'printf "usermod %s\\n" "\$*" >>"\$NMTK_FAKE_LOG"\n'
        '[[ -f "\$NMTK_GROUP_STATE" && -f "\$NMTK_USER_STATE" ]] || exit 6\n'
        '[[ " \$* " == *" --gid nmtk-deploy nmtk-deploy "* ]] || exit 65\n',
  );
  _writeExecutable(
    bin,
    'rm',
    '#!/bin/bash\n'
        'if [[ "\$*" == *"/etc/sudoers.d/nmtk-deploy"* ]]; then\n'
        '  printf "rm %s\\n" "\$*" >>"\$NMTK_FAKE_LOG"\n'
        '  exit 0\n'
        'fi\n'
        'exec /bin/rm "\$@"\n',
  );
  _writeExecutable(
    bin,
    'install',
    '#!/bin/bash\n'
        'printf "install %s\\n" "\$*" >>"\$NMTK_FAKE_LOG"\n'
        '[[ "\$1" == "-d" ]] || exit 0\n'
        'mkdir -p "\${!#}"\n',
  );

  final completeScript = ClientDeploymentService.buildRemoteBootstrapScript(
    containerEngine: 'docker',
    factoryReset: false,
  );
  final preflightIndex = completeScript.indexOf(
    '\nphase "preflight_running"',
  );
  final accountIndex = completeScript.indexOf(
    '\nphase "bootstrapping_access"',
  );
  final credentialIndex = completeScript.indexOf(
    '\ncapture_step 30 "deploy_account_failed" 26 \\\n'
    '  "Preparing deployment credential workspace"',
    accountIndex,
  );
  final accountScript = '${completeScript.substring(0, preflightIndex)}'
      '${completeScript.substring(accountIndex, credentialIndex)}\n'
      'terminal "✓ Deployment account fixture completed"\n';
  final script = File('${fixture.path}/account.sh')
    ..writeAsStringSync(accountScript);
  final results = <ProcessResult>[
    for (var run = 0; run < runs; run += 1)
      Process.runSync(
        'bash',
        [script.path],
        environment: {
          ...Platform.environment,
          'PATH': '${bin.path}:/usr/bin:/bin',
          'NMTK_FAKE_LOG': commandLog.path,
          'NMTK_USER_STATE': userState.path,
          'NMTK_GROUP_STATE': groupState.path,
          'NMTK_DEPLOY_HOME':
              invalidHome ? 'relative/deploy-home' : deployHome.path,
          'NMTK_FAIL_GROUP_CREATION': '$failGroupCreation',
          'NMTK_FAKE_SECRET': 'temporary-admin-secret',
        },
      ),
  ];
  return (
    fixture: fixture,
    results: results,
    commandLog: commandLog.existsSync() ? commandLog.readAsStringSync() : '',
  );
}

({
  Directory fixture,
  ProcessResult result,
  String commandLog,
}) _runDeploymentCredentialFixture({
  bool failKeyGeneration = false,
}) {
  final fixture = Directory.systemTemp.createTempSync(
    'nmtk-deployment-credential-',
  );
  final bin = Directory('${fixture.path}/bin')..createSync();
  final deployHome = Directory('${fixture.path}/deploy-home')..createSync();
  final commandLog = File('${fixture.path}/commands.log');

  _writeExecutable(
    bin,
    'timeout',
    '#!/bin/bash\n'
        'while [[ "\$1" == --* ]]; do shift; done\n'
        'shift\n'
        'exec "\$@"\n',
  );
  _writeExecutable(
    bin,
    'id',
    '#!/bin/bash\n'
        'if [[ "\$1" == "-u" && \$# -eq 1 ]]; then echo 0; exit 0; fi\n'
        'if [[ "\$1" == "-u" ]]; then echo 48333; exit 0; fi\n'
        '[[ "\$1" == "nmtk-deploy" ]] && exit 0\n'
        'exit 1\n',
  );
  _writeExecutable(
    bin,
    'getent',
    '#!/bin/bash\n'
        'if [[ "\$1" == "group" && "\$2" == "nmtk-deploy" ]]; then\n'
        '  printf "nmtk-deploy:x:48333:\\n"\n'
        '  exit 0\n'
        'fi\n'
        'if [[ "\$1" == "passwd" ]]; then\n'
        '  printf "nmtk-deploy:x:48333:48333::%s:/bin/bash\\n" '
        '"\$NMTK_DEPLOY_HOME"\n'
        '  exit 0\n'
        'fi\n'
        'exit 1\n',
  );
  _writeExecutable(bin, 'usermod', '#!/bin/bash\nexit 0\n');
  _writeExecutable(
    bin,
    'install',
    '#!/bin/bash\n'
        'printf "install %s\\n" "\$*" >>"\$NMTK_FAKE_LOG"\n'
        'for argument in "\$@"; do\n'
        '  case "\$argument" in\n'
        '    *.pub) [[ -f "\$argument" ]] || exit 88 ;;\n'
        '  esac\n'
        'done\n',
  );
  _writeExecutable(
    bin,
    'ssh-keygen',
    '#!/bin/bash\n'
        'arguments=("\$@")\n'
        'key_path=""\n'
        'for ((index=0; index < \${#arguments[@]}; index++)); do\n'
        '  if [[ "\${arguments[\$index]}" == "-f" ]]; then\n'
        '    key_path="\${arguments[\$((index + 1))]}"\n'
        '    break\n'
        '  fi\n'
        'done\n'
        'printf "key-path %s\\n" "\$key_path" >>"\$NMTK_FAKE_LOG"\n'
        'if [[ -e "\$key_path" ]]; then\n'
        '  printf "key-path-already-existed\\n" >>"\$NMTK_FAKE_LOG"\n'
        '  exit 89\n'
        'fi\n'
        '${failKeyGeneration ? 'exit 42\n' : ''}'
        'exec /usr/bin/ssh-keygen "\${arguments[@]}"\n',
  );

  final completeScript = ClientDeploymentService.buildRemoteBootstrapScript(
    containerEngine: 'docker',
    factoryReset: false,
  );
  final preflightIndex = completeScript.indexOf(
    '\nphase "preflight_running"',
  );
  final accountIndex = completeScript.indexOf(
    '\nphase "bootstrapping_access"',
  );
  final credentialScript = '${completeScript.substring(0, preflightIndex)}'
      '${completeScript.substring(accountIndex)}';
  final script = File('${fixture.path}/credential.sh')
    ..writeAsStringSync(credentialScript);
  final result = Process.runSync(
    'bash',
    [script.path],
    environment: {
      ...Platform.environment,
      'PATH': '${bin.path}:/usr/bin:/bin',
      'NMTK_FAKE_LOG': commandLog.path,
      'NMTK_DEPLOY_HOME': deployHome.path,
    },
  );
  return (
    fixture: fixture,
    result: result,
    commandLog: commandLog.existsSync() ? commandLog.readAsStringSync() : '',
  );
}

({
  ProcessResult result,
  String commandLog,
}) _runPodmanApiProvisioningFixture({
  int systemctlEnableExit = 0,
  int systemctlStartExit = 0,
  bool systemctlCreatesSocket = false,
  bool requireFallbackForRemoteApi = false,
  bool fallbackCreatesSocket = true,
}) {
  // Unix-domain socket paths are limited to roughly 100 bytes on macOS, so
  // keep this fixture under the short /tmp alias instead of Platform.systemTemp.
  final fixture = Directory('/tmp').createTempSync('nmtk-podman-api-');
  final bin = Directory('${fixture.path}/bin')..createSync();
  final deployHome = Directory('${fixture.path}/deploy-home')..createSync();
  final runtime = Directory('${fixture.path}/run-user/48334/podman')
    ..createSync(recursive: true);
  final socket = '${runtime.path}/podman.sock';
  final commandLog = File('${fixture.path}/commands.log');
  final fallbackMarker = File('${fixture.path}/fallback-started');
  final servicePid = File('${fixture.path}/service.pid');

  _writeExecutable(
    bin,
    'timeout',
    '#!/bin/bash\n'
        'while [[ "\$1" == --* ]]; do shift; done\n'
        'shift\n'
        'exec "\$@"\n',
  );
  _writeExecutable(
    bin,
    'runuser',
    '#!/bin/bash\n'
        'while [[ "\$1" != "--" ]]; do shift; done\n'
        'shift\n'
        'exec "\$@"\n',
  );
  _writeExecutable(
    bin,
    'systemctl',
    '#!/bin/bash\n'
        'printf "systemctl %s\\n" "\$*" >>"\$NMTK_FAKE_LOG"\n'
        'if [[ "\$*" == *" enable podman.socket"* ]]; then\n'
        '  exit "\$NMTK_SYSTEMCTL_ENABLE_EXIT"\n'
        'fi\n'
        'if [[ "\$*" == *" start podman.socket"* ]]; then\n'
        '  if [[ "\$NMTK_SYSTEMD_CREATES_SOCKET" == "true" ]]; then\n'
        "    python3 -c 'import socket,sys,time; "
        'time.sleep(.08); s=socket.socket(socket.AF_UNIX); '
        "s.bind(sys.argv[1]); s.listen(1); time.sleep(10)' "
        '"\$NMTK_SOCKET" >/dev/null 2>&1 &\n'
        '    printf "%s\\n" "\$!" >"\$NMTK_SERVICE_PID"\n'
        '  fi\n'
        '  exit "\$NMTK_SYSTEMCTL_START_EXIT"\n'
        'fi\n'
        'exit 0\n',
  );
  _writeExecutable(
    bin,
    'setsid',
    '#!/bin/bash\n'
        'printf "fallback %s\\n" "\$*" >>"\$NMTK_FAKE_LOG"\n'
        'touch "\$NMTK_FALLBACK_MARKER"\n'
        '[[ "\$NMTK_FALLBACK_CREATES_SOCKET" == "true" ]] || exit 1\n'
        "python3 -c 'import socket,sys,time; "
        's=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); '
        "s.listen(1); time.sleep(10)' "
        '"\$NMTK_SOCKET" >/dev/null 2>&1 &\n'
        'printf "%s\\n" "\$!" >"\$NMTK_SERVICE_PID"\n',
  );
  _writeExecutable(
    bin,
    'podman',
    '#!/bin/bash\n'
        'printf "podman %s\\n" "\$*" >>"\$NMTK_FAKE_LOG"\n'
        'if [[ "\$1" == "--remote" ]]; then\n'
        '  if [[ "\$NMTK_REQUIRE_FALLBACK" == "true" && '
        '! -f "\$NMTK_FALLBACK_MARKER" ]]; then\n'
        '    exit 125\n'
        '  fi\n'
        '  printf "version=fixture rootless=true storage=fixture\\n"\n'
        '  exit 0\n'
        'fi\n'
        'exit 1\n',
  );

  final completeScript = ClientDeploymentService.buildRemoteBootstrapScript(
    containerEngine: 'podman',
    factoryReset: false,
  );
  final preflightIndex = completeScript.indexOf(
    '\nif [ "\$(id -u)"',
  );
  final startIndex = completeScript.indexOf(
    '  NMTK_SETUP_AUTOMATIC_RECOVERY=true \\\n'
    '  capture_step 30 "podman_api_start_failed" 27 \\\n'
    '    "Starting or repairing rootless Podman API"',
  );
  final endIndex = completeScript.indexOf(
    '\nfi\n\nstep_marker start 40 false '
    '"Finalizing secure deployment handoff"',
    startIndex,
  );
  final provisioningScript = '${completeScript.substring(0, preflightIndex)}\n'
      'DEPLOY_HOME=${jsonEncode(deployHome.path)}\n'
      'DEPLOY_UID=48334\n'
      '${completeScript.substring(startIndex, endIndex)}\n'
      'terminal "✓ Podman API fixture completed"\n';
  final script = File('${fixture.path}/provision.sh')
    ..writeAsStringSync(
      provisioningScript
          .replaceAll(
            r'/run/user/$DEPLOY_UID',
            Directory(runtime.path).parent.path,
          )
          .replaceAll('sleep 0.5', 'sleep 0.1'),
    );
  final result = Process.runSync(
    'bash',
    [script.path],
    environment: {
      ...Platform.environment,
      'PATH': '${bin.path}:/usr/bin:/bin',
      'NMTK_FAKE_LOG': commandLog.path,
      'NMTK_SOCKET': socket,
      'NMTK_FALLBACK_MARKER': fallbackMarker.path,
      'NMTK_SERVICE_PID': servicePid.path,
      'NMTK_SYSTEMCTL_ENABLE_EXIT': '$systemctlEnableExit',
      'NMTK_SYSTEMCTL_START_EXIT': '$systemctlStartExit',
      'NMTK_SYSTEMD_CREATES_SOCKET': '$systemctlCreatesSocket',
      'NMTK_REQUIRE_FALLBACK': '$requireFallbackForRemoteApi',
      'NMTK_FALLBACK_CREATES_SOCKET': '$fallbackCreatesSocket',
    },
  );
  final log = commandLog.existsSync() ? commandLog.readAsStringSync() : '';
  if (servicePid.existsSync()) {
    final pid = servicePid.readAsStringSync().trim();
    Process.runSync('kill', ['-KILL', pid]);
  }
  fixture.deleteSync(recursive: true);
  return (result: result, commandLog: log);
}

Future<DeploymentPersistence> _completedRemotePersistence() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final persistence = DeploymentPersistence(
    preferences: await SharedPreferences.getInstance(),
    secureStorage: _MemorySecretStorage(),
  );
  const target = DeploymentTarget(
    id: 'remote',
    displayName: 'Remote backend',
    targetType: 'remote_host',
    mode: 'docker',
    authMode: 'ssh_key',
    host: 'server.example',
    backendPort: 9000,
  );
  await persistence.saveTarget(
    target,
    const DeploymentRequest(
      targetType: 'remote_host',
      mode: 'docker',
      displayName: 'Remote backend',
      host: 'server.example',
    ),
  );
  await persistence.saveActiveJob(
    const DeploymentJob(
      id: 'job',
      targetId: 'remote',
      mode: 'docker',
      stage: 'completed',
      percent: 100,
      stageLabel: 'Backend and launcher control are ready',
      logs: <String>[],
    ),
  );
  return persistence;
}

void main() {
  test(
      'deployment account reconciliation is idempotent for every partial state',
      () {
    final cases = <({
      String name,
      bool userExists,
      bool groupExists,
      int groupAdds,
      int userAdds,
      int userMods,
    })>[
      (
        name: 'neither exists',
        userExists: false,
        groupExists: false,
        groupAdds: 1,
        userAdds: 1,
        userMods: 1,
      ),
      (
        name: 'group only',
        userExists: false,
        groupExists: true,
        groupAdds: 0,
        userAdds: 1,
        userMods: 1,
      ),
      (
        name: 'user only',
        userExists: true,
        groupExists: false,
        groupAdds: 1,
        userAdds: 0,
        userMods: 2,
      ),
      (
        name: 'both exist',
        userExists: true,
        groupExists: true,
        groupAdds: 0,
        userAdds: 0,
        userMods: 2,
      ),
    ];

    for (final testCase in cases) {
      final fixture = _runDeploymentAccountFixture(
        userExists: testCase.userExists,
        groupExists: testCase.groupExists,
        runs: 2,
      );
      addTearDown(() {
        if (fixture.fixture.existsSync()) {
          fixture.fixture.deleteSync(recursive: true);
        }
      });
      final output = fixture.results
          .map((result) => '${result.stdout}\n${result.stderr}')
          .join('\n');

      expect(
        fixture.results.map((result) => result.exitCode),
        everyElement(0),
        reason: '${testCase.name}\n$output\n${fixture.commandLog}',
      );
      expect(
        RegExp(r'^groupadd ', multiLine: true)
            .allMatches(fixture.commandLog)
            .length,
        testCase.groupAdds,
        reason: testCase.name,
      );
      expect(
        RegExp(r'^useradd ', multiLine: true)
            .allMatches(fixture.commandLog)
            .length,
        testCase.userAdds,
        reason: testCase.name,
      );
      expect(
        RegExp(r'^usermod ', multiLine: true)
            .allMatches(fixture.commandLog)
            .length,
        testCase.userMods,
        reason: testCase.name,
      );
      if (!testCase.userExists) {
        expect(
          fixture.commandLog,
          contains(
            'useradd --create-home --shell /bin/bash '
            '--gid nmtk-deploy nmtk-deploy',
          ),
          reason: testCase.name,
        );
      }
      expect(
        output,
        contains('✓ Deployment account fixture completed'),
        reason: testCase.name,
      );
    }
  });

  test('deployment account failures are actionable and redact credentials', () {
    final fixture = _runDeploymentAccountFixture(
      userExists: false,
      groupExists: false,
      failGroupCreation: true,
    );
    addTearDown(() {
      if (fixture.fixture.existsSync()) {
        fixture.fixture.deleteSync(recursive: true);
      }
    });
    final result = fixture.results.single;
    final output = '${result.stdout}\n${result.stderr}';
    final details = ClientDeploymentService.parseBootstrapFailureForTesting(
      output,
      exitCode: result.exitCode,
      rootPassword: 'temporary-admin-secret',
    );

    expect(result.exitCode, 25, reason: output);
    expect(output, contains('NMTK_SETUP_ERROR|deploy_account_failed|'));
    expect(details.code, 'deploy_account_failed');
    expect(details.summary, 'The deployment account could not be prepared');
    expect(details.recovery, contains('Restart the server'));
    expect(details.recovery, contains('Retry setup'));
    expect(details.technicalDetails, contains('password=[redacted]'));
    expect(
      details.technicalDetails,
      isNot(contains('temporary-admin-secret')),
    );
  });

  test('deployment account rejects an unsafe home directory', () {
    final fixture = _runDeploymentAccountFixture(
      userExists: true,
      groupExists: true,
      invalidHome: true,
    );
    addTearDown(() {
      if (fixture.fixture.existsSync()) {
        fixture.fixture.deleteSync(recursive: true);
      }
    });
    final result = fixture.results.single;
    final output = '${result.stdout}\n${result.stderr}';

    expect(result.exitCode, 25, reason: output);
    expect(output, contains('Deployment account has no valid home directory'));
    expect(output, contains('NMTK_SETUP_ERROR|deploy_account_failed|'));
    expect(
      fixture.commandLog,
      isNot(contains('install -d -m 750')),
      reason: 'A relative home path must never be created.',
    );
  });

  test('remote bootstrap reconciles both runtimes without broad sudo access',
      () {
    final script = ClientDeploymentService.buildRemoteBootstrapScript(
      containerEngine: 'docker',
      factoryReset: false,
    );

    expect(script, contains(r'for project in $PROJECTS'));
    expect(script, contains('remove_runtime_objects docker'));
    expect(script, contains('remove_runtime_objects podman'));
    expect(script, contains(r'runuser -u "$candidate"'));
    expect(script, contains('com.docker.compose.project'));
    expect(script, contains('io.podman.compose.project'));
    expect(script, contains('jupyter-server)'));
    expect(script, contains(r'{{.ID}} {{.Names}}'));
    expect(script, isNot(contains('NOPASSWD:ALL')));
    expect(script, contains('FACTORY_RESET="false"'));
    expect(script, contains('NMTK_SETUP_PHASE|'));
    expect(script, contains('NMTK_SETUP_ERROR|'));
    expect(script, contains('NMTK_SETUP_TERMINAL|'));
    expect(script, contains('capture_step 20'));
    expect(script, contains('capture_step 60'));
    expect(script, contains('capture_step 300'));
    expect(script, contains('--kill-after=5s'));
    expect(script, contains('</dev/null'));
    expect(script, contains('mktemp -d /tmp/nmtk-deploy-key.XXXXXX'));
    expect(
      script,
      contains(r'TEMPORARY_KEY="$TEMPORARY_KEY_DIR/id_ed25519"'),
    );
    expect(
      script,
      isNot(contains('mktemp /tmp/nmtk-deploy-key.XXXXXX')),
    );
    expect(script, contains('✓ Administrator privileges confirmed'));
    expect(
      script,
      contains(r'default_storage="$home/.local/share/containers/storage"'),
    );
    expect(
      script,
      contains(r'mktemp -d "/tmp/nmtk-podman-runtime.${uid}.XXXXXX"'),
    );
    expect(script, contains(r'"podman (user $candidate)"'));
    expect(script, isNot(contains(r'$runtime (${prefix[*]})')));
    expect(
      ClientDeploymentService.administratorShellCommand(needsSudo: false),
      'bash',
    );
    expect(
      ClientDeploymentService.administratorShellCommand(needsSudo: true),
      'sudo -S -p "" bash',
    );
  });

  test('bootstrap failure markers produce actionable sanitized diagnostics',
      () {
    final details = ClientDeploymentService.parseBootstrapFailureForTesting(
      'sudo output temporary-admin-secret\n'
      'NMTK_SETUP_ERROR|podman_inspection_failed|'
      'reconciling_existing_install|29|Podman is inaccessible.',
      exitCode: 29,
      rootPassword: 'temporary-admin-secret',
    );

    expect(details.code, 'podman_inspection_failed');
    expect(details.phase, 'reconciling_existing_install');
    expect(details.summary, 'Podman installations could not be inspected');
    expect(details.recovery, contains('Administrator access succeeded'));
    expect(details.exitCode, 29);
    expect(details.technicalDetails, isNot(contains('temporary-admin-secret')));
    expect(details.technicalDetails, contains('[redacted]'));
  });

  test(
      'dormant Podman user gets a temporary runtime while unrelated users are skipped',
      () {
    final fixture = _runRootlessReconciliationFixture();
    final combinedOutput = '${fixture.result.stdout}\n${fixture.result.stderr}';

    expect(
      fixture.result.exitCode,
      0,
      reason: combinedOutput,
    );
    expect(
      combinedOutput,
      contains(
        'NMTK_SETUP_COMMAND|runuser -u ${fixture.dormantUser} -- env',
      ),
    );
    expect(combinedOutput, contains('podman info'));
    expect(
      fixture.commandLog,
      contains('runuser -u ${fixture.dormantUser}'),
    );
    expect(fixture.commandLog, isNot(contains(fixture.skippedUser)));
    expect(combinedOutput, contains('level=warning msg="fixture warning"'));
    expect(
      fixture.commandLog,
      isNot(contains('podman rm -f time=')),
      reason: 'stderr warnings must never be treated as object identifiers.',
    );
    final runtimeMatch = RegExp(
      r'XDG_RUNTIME_DIR=(/tmp/nmtk-podman-runtime\.[^\s]+)',
    ).firstMatch(fixture.commandLog);
    expect(runtimeMatch, isNotNull);
    final runtimeDirectory = runtimeMatch!.group(1)!;
    expect(
      fixture.commandLog,
      contains('chown 48331:48331 $runtimeDirectory'),
    );
    expect(
      Directory(runtimeDirectory).existsSync(),
      isFalse,
      reason: 'The temporary runtime must be removed by the EXIT trap.',
    );
  });

  test('valid stale container IDs are removed but malformed IDs are rejected',
      () {
    final valid = _runRootlessReconciliationFixture(
      discoveredContainerOutput: 'deadbeefcafe',
    );
    expect(valid.result.exitCode, 0, reason: '${valid.result.stderr}');
    expect(valid.commandLog, contains('podman rm -f deadbeefcafe'));

    final malformed = _runRootlessReconciliationFixture(
      discoveredContainerOutput: 'time="warning"',
    );
    final malformedOutput =
        '${malformed.result.stdout}\n${malformed.result.stderr}';
    expect(malformed.result.exitCode, 29, reason: malformedOutput);
    expect(
      malformedOutput,
      contains('returned an invalid container identifier'),
    );
    expect(
      malformed.commandLog,
      isNot(contains('podman rm -f time=')),
    );
  });

  test('factory reset removes only validated NMTK volume names', () {
    final preserve = _runRootlessReconciliationFixture(
      discoveredVolumeOutput: 'nmtk_workspace',
    );
    expect(preserve.result.exitCode, 0, reason: '${preserve.result.stderr}');
    expect(preserve.commandLog, isNot(contains('volume rm -f')));

    final reset = _runRootlessReconciliationFixture(
      factoryReset: true,
      discoveredVolumeOutput: 'nmtk_workspace',
    );
    expect(reset.result.exitCode, 0, reason: '${reset.result.stderr}');
    expect(reset.commandLog, contains('volume rm -f nmtk_workspace'));
  });

  test('a responding command that never exits is terminated as a process group',
      () {
    final completeScript = ClientDeploymentService.buildRemoteBootstrapScript(
      containerEngine: 'podman',
      factoryReset: false,
    );
    final firstCommand = completeScript.indexOf('\nif [ "\$(id -u)"');
    expect(firstCommand, greaterThan(0));
    final fixture = Directory.systemTemp.createTempSync('nmtk-hanging-step-');
    addTearDown(() {
      if (fixture.existsSync()) fixture.deleteSync(recursive: true);
    });
    final script = File('${fixture.path}/hang.sh')
      ..writeAsStringSync(
        '${completeScript.substring(0, firstCommand)}\n'
        'capture_step 1 deploy_account_failed 27 "systemctl --user enable" '
        '"socket enabled" bash -c '
        "'echo \"Created symlink podman.socket\"; "
        "while true; do sleep 1; done'\n",
      );

    final stopwatch = Stopwatch()..start();
    final result = Process.runSync('bash', [script.path]);
    stopwatch.stop();
    final output = '${result.stdout}\n${result.stderr}';

    expect(result.exitCode, 27, reason: output);
    expect(output, contains('Created symlink podman.socket'));
    expect(
      output,
      contains(
        'NMTK_SETUP_STEP|start|1|false|systemctl --user enable',
      ),
    );
    expect(
      output,
      contains(
        'NMTK_SETUP_STEP|finish|1|false|systemctl --user enable',
      ),
    );
    expect(output, contains('NMTK_SETUP_COMMAND_EXIT|timeout|1'));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 6)));
    expect(completeScript, isNot(contains('timeout --foreground')));
  });

  test(
      'a successful command cannot leave transcript pipes open through a child',
      () {
    final completeScript = ClientDeploymentService.buildRemoteBootstrapScript(
      containerEngine: 'podman',
      factoryReset: false,
    );
    final firstCommand = completeScript.indexOf('\nif [ "\$(id -u)"');
    expect(firstCommand, greaterThan(0));
    final fixture = Directory.systemTemp.createTempSync(
      'nmtk-successful-leaked-child-',
    );
    addTearDown(() {
      if (fixture.existsSync()) fixture.deleteSync(recursive: true);
    });
    final script = File('${fixture.path}/leaked-child.sh')
      ..writeAsStringSync(
        '${completeScript.substring(0, firstCommand)}\n'
        'capture_step 5 deploy_account_failed 27 "podman info" '
        '"podman ready" bash -c '
        "'printf \"server-ready\\\\n\"; sleep 30 &'\n"
        'terminal "capture returned"\n',
      );

    final stopwatch = Stopwatch()..start();
    final result = Process.runSync('timeout', ['8s', 'bash', script.path]);
    stopwatch.stop();
    final output = '${result.stdout}\n${result.stderr}';

    expect(result.exitCode, 0, reason: output);
    expect(output, contains('server-ready'));
    expect(
      output,
      contains('NMTK_SETUP_STEP|start|5|false|podman info'),
    );
    expect(
      output,
      contains('NMTK_SETUP_STEP|finish|5|false|podman info'),
    );
    expect(output, contains('NMTK_SETUP_TERMINAL|capture returned'));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 6)));
  });

  test('an escaped writer cannot outlive the transcript drain deadline',
      () async {
    final setsidResult = Process.runSync(
      'sh',
      const ['-c', 'command -v setsid'],
    );
    if (setsidResult.exitCode != 0) return;
    final setsidPath = setsidResult.stdout.toString().trim();
    final completeScript = ClientDeploymentService.buildRemoteBootstrapScript(
      containerEngine: 'podman',
      factoryReset: false,
    );
    final firstCommand = completeScript.indexOf('\nif [ "\$(id -u)"');
    expect(firstCommand, greaterThan(0));
    final fixture = Directory.systemTemp.createTempSync(
      'nmtk-escaped-transcript-writer-',
    );
    final escapedPidFile = File('${fixture.path}/escaped.pid');
    addTearDown(() {
      if (escapedPidFile.existsSync()) {
        final escapedPid =
            int.tryParse(escapedPidFile.readAsStringSync().trim());
        if (escapedPid != null) {
          Process.runSync('kill', ['-KILL', '-$escapedPid']);
        }
      }
      if (fixture.existsSync()) fixture.deleteSync(recursive: true);
    });
    final writer = File('${fixture.path}/escape-writer.sh')
      ..writeAsStringSync(
        '#!/bin/bash\n'
        '$setsidPath -f bash -c '
        "'printf \"%s\\\\n\" \"\$\$\" >\"\$1\"; sleep 30' "
        '_ "\$NMTK_ESCAPE_PID_FILE"\n'
        'printf "escaped-ready\\n"\n',
      );
    Process.runSync('chmod', ['+x', writer.path]);
    final script = File('${fixture.path}/escaped-writer.sh')
      ..writeAsStringSync(
        '${completeScript.substring(0, firstCommand)}\n'
        'capture_step 5 deploy_account_failed 27 "podman info" '
        '"podman ready" ${writer.path}\n'
        'terminal "capture returned"\n',
      );

    final stopwatch = Stopwatch()..start();
    final result = Process.runSync(
      'timeout',
      ['8s', 'bash', script.path],
      environment: {
        ...Platform.environment,
        'NMTK_ESCAPE_PID_FILE': escapedPidFile.path,
      },
    );
    stopwatch.stop();
    final output = '${result.stdout}\n${result.stderr}';

    expect(result.exitCode, 0, reason: output);
    expect(output, contains('escaped-ready'));
    expect(output, contains('NMTK_SETUP_TERMINAL|capture returned'));
    for (var attempt = 0;
        attempt < 25 && !escapedPidFile.existsSync();
        attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(escapedPidFile.existsSync(), isTrue, reason: output);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 6)));
  });

  test('fallback Podman service detaches without transcript descriptors', () {
    final script = ClientDeploymentService.buildRemoteBootstrapScript(
      containerEngine: 'podman',
      factoryReset: false,
    );

    expect(script, contains('setsid -f podman system service --time=0'));
    expect(script, contains('podman --remote --url "\$remote_url" info'));
    expect(
      script,
      contains(
        '</dev/null >"\$HOME/.nmtk-podman-service.log" 2>&1',
      ),
    );
    expect(script, isNot(contains('nohup podman system service')));
    expect(script, contains('setsid is required'));
  });

  test(
      'systemctl success without a usable Podman socket triggers automatic fallback',
      () {
    final fixture = _runPodmanApiProvisioningFixture();
    final output = '${fixture.result.stdout}\n${fixture.result.stderr}';

    expect(
      fixture.result.exitCode,
      0,
      reason: '$output\n${fixture.commandLog}',
    );
    expect(
        fixture.commandLog, contains('systemctl --user start podman.socket'));
    expect(fixture.commandLog, contains('fallback -f podman system service'));
    expect(
      fixture.commandLog,
      contains('podman --remote --url unix://'),
    );
    expect(
      output,
      contains(
        'NMTK_SETUP_STEP|start|30|true|'
        'Starting or repairing rootless Podman API',
      ),
    );
    expect(output, contains('✓ Podman API fixture completed'));
  });

  test('missing user D-Bus cannot block the Podman fallback', () {
    final fixture = _runPodmanApiProvisioningFixture(
      systemctlEnableExit: 1,
      systemctlStartExit: 1,
    );
    final output = '${fixture.result.stdout}\n${fixture.result.stderr}';

    expect(
      fixture.result.exitCode,
      0,
      reason: '$output\n${fixture.commandLog}',
    );
    expect(
      fixture.commandLog,
      contains('systemctl --user enable podman.socket'),
    );
    expect(
      fixture.commandLog,
      contains('systemctl --user start podman.socket'),
    );
    expect(fixture.commandLog, contains('fallback -f podman system service'));
    expect(output, contains('✓ Podman API fixture completed'));
    expect(
      output,
      isNot(contains('NMTK_SETUP_ERROR|deploy_account_failed|')),
    );
  });

  test('a delayed healthy systemd Podman socket avoids fallback startup', () {
    final fixture = _runPodmanApiProvisioningFixture(
      systemctlCreatesSocket: true,
    );
    final output = '${fixture.result.stdout}\n${fixture.result.stderr}';

    expect(fixture.result.exitCode, 0, reason: output);
    expect(
        fixture.commandLog, contains('systemctl --user start podman.socket'));
    expect(fixture.commandLog, isNot(contains('fallback ')));
    expect(output, contains('✓ Podman API fixture completed'));
  });

  test('an unresponsive systemd Podman socket is replaced by fallback', () {
    final fixture = _runPodmanApiProvisioningFixture(
      systemctlCreatesSocket: true,
      requireFallbackForRemoteApi: true,
    );
    final output = '${fixture.result.stdout}\n${fixture.result.stderr}';

    expect(fixture.result.exitCode, 0, reason: output);
    expect(fixture.commandLog, contains('systemctl --user stop podman.socket'));
    expect(fixture.commandLog, contains('fallback -f podman system service'));
    expect(output, contains('✓ Podman API fixture completed'));
  });

  test('failed systemd and fallback Podman startup exits actionably', () {
    final fixture = _runPodmanApiProvisioningFixture(
      systemctlStartExit: 1,
      fallbackCreatesSocket: false,
    );
    final output = '${fixture.result.stdout}\n${fixture.result.stderr}';

    expect(fixture.result.exitCode, 27, reason: output);
    expect(
      output,
      contains(
        'The rootless Podman API did not become ready after automatic recovery.',
      ),
    );
    expect(
      output,
      contains('NMTK_SETUP_ERROR|podman_api_start_failed|'),
    );
    expect(output, isNot(contains('NMTK_DEPLOY_PRIVATE_KEY_B64=')));

    final details = ClientDeploymentService.parseBootstrapFailureForTesting(
      output,
      exitCode: fixture.result.exitCode,
    );
    expect(details.summary, 'The Podman service could not be started');
    expect(details.recovery, contains('Restart the server'));
    expect(details.recovery, contains('Set up and connect'));
  });

  test('privilege drops do not inherit the administrator home directory', () {
    final script = ClientDeploymentService.buildRemoteBootstrapScript(
      containerEngine: 'podman',
      factoryReset: false,
    );
    expect(
      script.indexOf('\ncd /\n'),
      lessThan(script.indexOf('runuser -u')),
      reason: 'the working directory must be safe before the first runuser',
    );

    final fixture = _runRootlessReconciliationFixture(
      requireRootWorkingDirectory: true,
    );
    final combinedOutput = '${fixture.result.stdout}\n${fixture.result.stderr}';

    expect(fixture.result.exitCode, 0, reason: combinedOutput);
    expect(combinedOutput, isNot(contains('cannot chdir to')));
    expect(fixture.commandLog, contains('runuser -u ${fixture.dormantUser}'));
    expect(combinedOutput, isNot(contains('Skipped Podman accounts:')));
  });

  test('an unreadable account is skipped instead of failing setup', () {
    final fixture = _runRootlessReconciliationFixture(candidateInfoExit: 1);
    final combinedOutput = '${fixture.result.stdout}\n${fixture.result.stderr}';

    expect(fixture.result.exitCode, 0, reason: combinedOutput);
    expect(
      combinedOutput,
      contains(
        'Could not read the Podman setup of account ${fixture.dormantUser}',
      ),
    );
    expect(
      combinedOutput,
      contains('Skipped Podman accounts: ${fixture.dormantUser}'),
    );
    expect(combinedOutput, contains('✓ Reconciliation fixture completed'));
  });

  test("the server's own unreadable Podman still stops setup", () {
    final fixture = _runRootlessReconciliationFixture(rootInfoExit: 1);
    final combinedOutput = '${fixture.result.stdout}\n${fixture.result.stderr}';

    expect(fixture.result.exitCode, 29, reason: combinedOutput);
    expect(
      combinedOutput,
      contains('NMTK_SETUP_ERROR|podman_inspection_failed|'),
    );
    expect(
      combinedOutput,
      isNot(contains('✓ Reconciliation fixture completed')),
    );
  });

  test('unsafe active Podman runtime ownership skips only that account', () {
    final fixture = _runRootlessReconciliationFixture(
      unsafeActiveRuntime: true,
    );
    final combinedOutput = '${fixture.result.stdout}\n${fixture.result.stderr}';

    // Somebody else's misowned runtime directory says nothing about whether
    // this server can host NMTK, so setup finishes and names the account it
    // left alone.
    expect(fixture.result.exitCode, 0, reason: combinedOutput);
    expect(
      combinedOutput,
      contains(
        'Could not read the Podman setup of account ${fixture.dormantUser}',
      ),
    );
    expect(
      combinedOutput,
      contains('Skipped Podman accounts: ${fixture.dormantUser}'),
    );
    expect(
      fixture.commandLog,
      isNot(contains('runuser -u ${fixture.dormantUser}')),
    );
  });

  test('temporary Podman runtime cleanup failures name the affected user', () {
    final fixture = _runRootlessReconciliationFixture(
      failRuntimeCleanup: true,
    );
    final combinedOutput = '${fixture.result.stdout}\n${fixture.result.stderr}';

    expect(fixture.result.exitCode, 29, reason: combinedOutput);
    expect(
      combinedOutput,
      contains(
        'Temporary Podman runtime cleanup failed for user '
        '${fixture.dormantUser}',
      ),
    );
    expect(
      combinedOutput,
      contains(
        'Administrator access succeeded, but the temporary Podman runtime '
        'for user ${fixture.dormantUser} could not be removed.',
      ),
    );
  });

  test('deployment credential generation uses a new path and cleans it', () {
    final fixture = _runDeploymentCredentialFixture();
    addTearDown(() {
      if (fixture.fixture.existsSync()) {
        fixture.fixture.deleteSync(recursive: true);
      }
    });
    final combinedOutput = '${fixture.result.stdout}\n${fixture.result.stderr}';

    expect(fixture.result.exitCode, 0, reason: combinedOutput);
    expect(
      combinedOutput,
      contains('NMTK_SETUP_COMMAND|ssh-keygen -q -t ed25519'),
    );
    expect(
      combinedOutput,
      isNot(contains('✓ Deployment credential generated')),
    );
    expect(fixture.commandLog, isNot(contains('key-path-already-existed')));
    final keyPath = RegExp(
      r'key-path (/[^\s]+)',
    ).firstMatch(fixture.commandLog)?.group(1);
    expect(keyPath, isNotNull);
    expect(keyPath, endsWith('/id_ed25519'));
    expect(Directory(File(keyPath!).parent.path).existsSync(), isFalse);
    final encodedKey = RegExp(
      r'NMTK_DEPLOY_PRIVATE_KEY_B64=([A-Za-z0-9+/=]+)',
    ).firstMatch(fixture.result.stdout.toString())?.group(1);
    expect(encodedKey, isNotNull);
    expect(
      utf8.decode(base64Decode(encodedKey!)),
      contains('BEGIN OPENSSH PRIVATE KEY'),
    );
    expect(
      combinedOutput,
      contains(
        'NMTK_SETUP_STEP|start|40|false|'
        'Finalizing secure deployment handoff',
      ),
    );
    expect(
      combinedOutput,
      contains(
        'NMTK_SETUP_STEP|finish|40|false|'
        'Finalizing secure deployment handoff',
      ),
    );
    expect(
      combinedOutput.indexOf('NMTK_DEPLOY_PRIVATE_KEY_B64='),
      lessThan(
        combinedOutput.indexOf(
          'NMTK_SETUP_STEP|finish|40|false|'
          'Finalizing secure deployment handoff',
        ),
      ),
    );
    expect(combinedOutput, isNot(contains('Overwrite (y/n)?')));
  });

  test('failed credential generation still removes its private workspace', () {
    final fixture = _runDeploymentCredentialFixture(
      failKeyGeneration: true,
    );
    addTearDown(() {
      if (fixture.fixture.existsSync()) {
        fixture.fixture.deleteSync(recursive: true);
      }
    });
    final combinedOutput = '${fixture.result.stdout}\n${fixture.result.stderr}';

    expect(fixture.result.exitCode, 26, reason: combinedOutput);
    expect(
      combinedOutput,
      contains('NMTK_SETUP_COMMAND_EXIT|exit|42'),
    );
    final keyPath = RegExp(
      r'key-path (/[^\s]+)',
    ).firstMatch(fixture.commandLog)?.group(1);
    expect(keyPath, isNotNull);
    expect(Directory(File(keyPath!).parent.path).existsSync(), isFalse);
  });

  test('unknown bootstrap failures retain bounded output without credentials',
      () {
    final details = ClientDeploymentService.parseBootstrapFailureForTesting(
      '${List<String>.filled(9000, 'x').join()}\nadmin-private-key',
      exitCode: 2,
      rootPrivateKey: 'admin-private-key',
    );

    expect(details.code, 'unknown_bootstrap_failure');
    expect(details.technicalDetails, startsWith('… output truncated …'));
    expect(details.technicalDetails.length, lessThanOrEqualTo(8030));
    expect(details.technicalDetails, isNot(contains('admin-private-key')));
  });

  test('bootstrap transcript exposes raw output and hides protocol markers',
      () {
    expect(
      ClientDeploymentService.parseBootstrapTranscriptLineForTesting(
        r'NMTK_SETUP_COMMAND|podman info',
      ),
      r'$ podman info',
    );
    expect(
      ClientDeploymentService.parseBootstrapTranscriptLineForTesting(
        'host: amd64',
      ),
      'host: amd64',
    );
    expect(
      ClientDeploymentService.parseBootstrapTranscriptLineForTesting(
        'NMTK_SETUP_TERMINAL|✓ Podman is accessible',
      ),
      isNull,
    );
    expect(
      ClientDeploymentService.parseBootstrapTranscriptLineForTesting(
        'NMTK_SETUP_PHASE|preflight_running|7|Checking server',
      ),
      isNull,
    );
    expect(
      ClientDeploymentService.parseBootstrapTranscriptLineForTesting(
        'NMTK_SETUP_STEP|start|20|true|Verifying rootless Podman API',
      ),
      isNull,
    );
    expect(
      ClientDeploymentService.parseBootstrapTranscriptLineForTesting(
        'NMTK_DEPLOY_PRIVATE_KEY_B64=cHJpdmF0ZQ==',
      ),
      isNull,
    );
    expect(
      ClientDeploymentService.parseBootstrapTranscriptLineForTesting(
        'password=temporary-secret \x1b[31mfailed\x1b[0m',
        rootPassword: 'temporary-secret',
      ),
      'password=[redacted] failed',
    );
    expect(
      ClientDeploymentService.parseBootstrapTranscriptLineForTesting(
        'NMTK_SETUP_COMMAND_EXIT|exit|125',
      ),
      '[client: command exited 125]',
    );
  });

  test('bootstrap operation markers contain only safe progress metadata', () {
    final started =
        ClientDeploymentService.parseBootstrapOperationMarkerForTesting(
      'NMTK_SETUP_STEP|start|20|true|Verifying rootless Podman API',
    );
    final finished =
        ClientDeploymentService.parseBootstrapOperationMarkerForTesting(
      'NMTK_SETUP_STEP|finish|20|true|Verifying rootless Podman API',
    );

    expect(started?.state, 'start');
    expect(started?.timeoutSeconds, 20);
    expect(started?.automaticRecovery, isTrue);
    expect(started?.label, 'Verifying rootless Podman API');
    expect(finished?.state, 'finish');
    expect(
      ClientDeploymentService.parseBootstrapOperationMarkerForTesting(
        'NMTK_SETUP_STEP|start|20|true|password=secret|extra',
      ),
      isNull,
    );
  });

  test('client watchdog failures are structured and retryable', () {
    final details = ClientDeploymentService.administratorStepTimeoutForTesting(
      label: 'Verifying rootless Podman API',
      timeoutSeconds: 20,
      phase: 'bootstrapping_access',
    );

    expect(details.code, 'administrator_step_timeout');
    expect(details.phase, 'bootstrapping_access');
    expect(details.summary, 'Verifying rootless Podman API timed out');
    expect(details.recovery, contains('Select Retry'));
    expect(details.technicalDetails, contains('20-second command timeout'));
    expect(details.exitCode, 124);
  });

  test('a silent server between steps is reported instead of waited on', () {
    final details = ClientDeploymentService.administratorStallForTesting(
      phase: 'bootstrapping_access',
    );

    expect(details.code, 'administrator_stalled');
    expect(details.phase, 'bootstrapping_access');
    expect(details.summary, 'The server stopped reporting progress');
    expect(details.recovery, contains('Select Retry'));
    expect(details.exitCode, 124);
  });

  test('the administrator script announces its own exit on every path', () {
    final completeScript = ClientDeploymentService.buildRemoteBootstrapScript(
      containerEngine: 'podman',
      factoryReset: false,
    );
    final firstCommand = completeScript.indexOf('\nif [ "\$(id -u)"');
    expect(firstCommand, greaterThan(0));
    final prologue = completeScript.substring(0, firstCommand);
    final fixture = Directory.systemTemp.createTempSync('nmtk-done-marker-');
    addTearDown(() {
      if (fixture.existsSync()) fixture.deleteSync(recursive: true);
    });

    final success = File('${fixture.path}/success.sh')
      ..writeAsStringSync('$prologue\nterminal "✓ prepared"\n');
    final successResult = Process.runSync('bash', [success.path]);
    expect(successResult.exitCode, 0, reason: '${successResult.stderr}');
    expect(
      '${successResult.stdout}',
      contains('NMTK_SETUP_DONE|0'),
    );

    final failure = File('${fixture.path}/failure.sh')
      ..writeAsStringSync(
        '$prologue\nfail "deploy_account_failed" 25 "no account"\n',
      );
    final failureResult = Process.runSync('bash', [failure.path]);
    expect(failureResult.exitCode, 25);
    expect('${failureResult.stdout}', contains('NMTK_SETUP_DONE|25'));

    // The marker is protocol, not transcript: it must never reach the raw SSH
    // output the user reads.
    expect(
      ClientDeploymentService.parseBootstrapTranscriptLineForTesting(
        'NMTK_SETUP_DONE|0',
      ),
      isNull,
    );
  });

  test('a transcript stream that never closes cannot block setup', () async {
    // Reproduces the reported freeze: the script exits, but lingering rootless
    // Podman processes keep the SSH channel open, so the streams never reach
    // EOF. Setup used to wait here forever, leaving the app at 17%.
    final stdoutController = StreamController<String>();
    final stderrController = StreamController<String>();
    addTearDown(() async {
      await stdoutController.close();
      await stderrController.close();
    });
    final stdoutLines = <String>[];
    final stdout = stdoutController.stream.listen(stdoutLines.add);
    final stderr = stderrController.stream.listen((_) {});
    stdoutController.add('NMTK_SETUP_DONE|0');

    await ClientDeploymentService.drainTranscriptStreamsForTesting(
      stdout,
      stderr,
      timeout: const Duration(milliseconds: 50),
    ).timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('draining a held-open channel never returned'),
    );

    expect(stdoutLines, contains('NMTK_SETUP_DONE|0'));
  });

  test('a wedged progress write cannot block setup', () async {
    final wedged = Completer<void>();
    addTearDown(() {
      if (!wedged.isCompleted) wedged.complete();
    });

    await ClientDeploymentService.settleStreamedUpdatesForTesting(
      wedged.future,
      timeout: const Duration(milliseconds: 50),
    ).timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('settling a wedged progress write never returned'),
    );
  });

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

  test('terminal output bounds and replaces the remote install section', () {
    final bounded = ClientDeploymentService.boundTerminalOutputForTesting(
      List<String>.generate(2100, (index) => 'server output $index'),
    );
    expect(bounded.length, lessThanOrEqualTo(2000));
    expect(bounded.first, '[client: earlier SSH output truncated]');
    expect(bounded.last, 'server output 2099');

    final first = ClientDeploymentService.replaceRemoteInstallOutputForTesting(
      const <String>[r'$ uname -s', 'Linux'],
      const <String>['pulling image layer 1'],
    );
    final second = ClientDeploymentService.replaceRemoteInstallOutputForTesting(
      first,
      const <String>['pulling image layer 1', 'pulling image layer 2'],
    );
    expect(
      second.where((line) => line == 'pulling image layer 1'),
      hasLength(1),
    );
    expect(second, contains('pulling image layer 2'));
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

  test('remote setup creates a persisted job before SSH bootstrap completes',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final secrets = _MemorySecretStorage();
    final persistence = DeploymentPersistence(
      preferences: await SharedPreferences.getInstance(),
      secureStorage: secrets,
    );
    final service = ClientDeploymentService(
      assets: _ManifestAssetBundle(),
      persistenceFactory: () async => persistence,
      ssh: _BlockingSshDeploymentService(),
    );

    final job = await service.setupRemoteServer(
      const RemoteServerSetupRequest(
        host: '192.168.2.34',
        adminUsername: 'root',
        adminPassword: 'temporary-admin-secret',
        containerEngine: 'docker',
      ),
    );
    final snapshot = await service.load();

    expect(job.targetId, 'remote-192-168-2-34');
    expect(job.requiresEphemeralAdministrator, isTrue);
    expect(snapshot.activeJob?.id, job.id);
    expect(snapshot.activeJob?.stage, isNot('failed'));
    expect(
        secrets._values.toString(), isNot(contains('temporary-admin-secret')));
  });

  test('deployment bundle accepts exact slices from offset asset data',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final persistence = DeploymentPersistence(
      preferences: await SharedPreferences.getInstance(),
      secureStorage: _MemorySecretStorage(),
    );
    final service = ClientDeploymentService(
      assets: _ManifestAssetBundle(useOffsetByteData: true),
      persistenceFactory: () async => persistence,
      ssh: _BlockingSshDeploymentService(),
    );

    final job = await service.setupRemoteServer(
      const RemoteServerSetupRequest(
        host: '192.168.2.35',
        adminUsername: 'root',
        adminPassword: 'temporary-admin-secret',
        containerEngine: 'podman',
      ),
    );

    expect(job.bundleVersion, 5);
    expect(job.bundleManifestHash, hasLength(64));
    expect(persistence.loadActiveJob()?.id, job.id);
  });

  test('invalid deployment bundles fail before persistence or SSH setup',
      () async {
    final cases = <({String name, AssetBundle assets})>[
      (
        name: 'mismatched contents',
        assets: _ManifestAssetBundle(corruptedFile: 'docker-compose.yml'),
      ),
      (
        name: 'missing manifest entry',
        assets: _ManifestAssetBundle(omittedManifestFile: 'install.sh'),
      ),
      (
        name: 'unexpected manifest entry',
        assets: _ManifestAssetBundle(unexpectedManifestFile: 'unexpected.yml'),
      ),
    ];

    for (final testCase in cases) {
      var persistenceCalls = 0;
      final service = ClientDeploymentService(
        assets: testCase.assets,
        persistenceFactory: () async {
          persistenceCalls += 1;
          throw StateError('Persistence must not be reached.');
        },
        ssh: _BlockingSshDeploymentService(),
      );

      await expectLater(
        service.setupRemoteServer(
          const RemoteServerSetupRequest(
            host: '192.168.2.36',
            adminUsername: 'root',
            adminPassword: 'temporary-admin-secret',
            containerEngine: 'podman',
          ),
        ),
        throwsA(
          isA<StateError>()
              .having(
                (error) => error.message,
                'message',
                'This app build contains an inconsistent deployment bundle. '
                    'Update or reinstall NMTK, then retry setup. '
                    'The server was not changed.',
              )
              .having(
                (error) => error.toString(),
                'safe error',
                isNot(contains('temporary-admin-secret')),
              ),
        ),
        reason: testCase.name,
      );
      expect(persistenceCalls, 0, reason: testCase.name);
    }
  });

  test('factory reset is the only bootstrap mode that removes volumes', () {
    final preserve = ClientDeploymentService.buildRemoteBootstrapScript(
      containerEngine: 'podman',
      factoryReset: false,
    );
    final reset = ClientDeploymentService.buildRemoteBootstrapScript(
      containerEngine: 'podman',
      factoryReset: true,
    );

    expect(preserve, contains('FACTORY_RESET="false"'));
    expect(reset, contains('FACTORY_RESET="true"'));
    expect(reset, contains(r'"$runtime" volume rm -f'));
    expect(reset, contains(r'loginctl enable-linger "$DEPLOY_USER"'));
    expect(reset, contains('podman system service --time=0'));
  });

  test('generated administrator bootstrap script is valid Bash', () {
    final directory = Directory.systemTemp.createTempSync('nmtk-bootstrap-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final scriptFile = File('${directory.path}/bootstrap.sh')
      ..writeAsStringSync(
        ClientDeploymentService.buildRemoteBootstrapScript(
          containerEngine: 'docker',
          factoryReset: false,
        ),
      );

    final result = Process.runSync('bash', ['-n', scriptFile.path]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
  });

  test('deployment bundle verifies every uploaded asset checksum', () {
    const deploymentFiles = <String>[
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
    const checksum =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final bundle = DeploymentAssetBundle.fromManifestBytes(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'bundleVersion': 3,
            'files': {for (final file in deploymentFiles) file: checksum},
          }),
        ),
      ),
    );

    final parsed = DeploymentAssetBundle.parseRemoteChecksumOutput(
      <String>[
        for (final file in deploymentFiles) '$checksum  $file',
        '${bundle.manifestHash}  deployment-manifest.json',
      ].join('\n'),
    );

    expect(
      () => DeploymentAssetBundle.validateRemoteChecksums(
        bundle: bundle,
        actualChecksums: {
          for (final file in deploymentFiles) file: checksum,
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
          for (final file in deploymentFiles) file: checksum,
          'deployment-manifest.json': bundle.manifestHash,
        },
      ),
      returnsNormally,
    );
    expect(parsed, {
      for (final file in deploymentFiles) file: checksum,
      'deployment-manifest.json': bundle.manifestHash,
    });
  });

  test('deployment bundle reports unreadable checksum output separately', () {
    expect(
      () => DeploymentAssetBundle.parseRemoteChecksumOutput(
        'remote command did not produce checksums',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('unreadable output'),
        ),
      ),
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

  test('saving a remote target replaces older records for the same IP',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final persistence = DeploymentPersistence(
      preferences: await SharedPreferences.getInstance(),
      secureStorage: _MemorySecretStorage(),
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
  });

  test('does not retain completed when this device cannot reach the server',
      () async {
    final service = ClientDeploymentService(
      persistenceFactory: _completedRemotePersistence,
      httpClient:
          MockClient((_) async => throw http.ClientException('offline')),
    );

    final snapshot = await service.load();

    expect(snapshot.isReady, isFalse);
    expect(snapshot.activeJob?.stage, 'failed');
    expect(snapshot.activeJob?.error, contains('cannot reach'));
  });

  test('interrupted setup has no persisted target or deploy credential',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final secrets = _MemorySecretStorage();
    final persistence = DeploymentPersistence(
      preferences: await SharedPreferences.getInstance(),
      secureStorage: secrets,
    );
    await persistence.saveActiveJob(
      DeploymentJob(
        id: 'interrupted',
        targetId: 'remote-192-168-2-34',
        mode: 'docker',
        stage: 'uploading_assets',
        percent: 25,
        stageLabel: 'Uploading deployment bundle',
        logs: const <String>[],
        activeOperation: DeploymentActiveOperation(
          label: 'Installing Docker Engine',
          startedAt: DateTime.now(),
          timeoutSeconds: 300,
        ),
      ),
    );
    final service = ClientDeploymentService(
      persistenceFactory: () async => persistence,
    );

    final snapshot = await service.load();

    expect(snapshot.targets, isEmpty);
    expect(secrets._values, isEmpty);
    expect(snapshot.isReady, isFalse);
    expect(snapshot.activeJob?.stage, 'failed');
    expect(snapshot.activeJob?.error, contains('administrator credential'));
    expect(snapshot.activeJob?.activeOperation, isNull);
  });

  test('retains completion only after desktop-visible NeuroStudio readiness',
      () async {
    final service = ClientDeploymentService(
      persistenceFactory: _completedRemotePersistence,
      httpClient: MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/api/launcher/modules/neurocnl/start') {
          return http.Response('{}', 202);
        }
        if (request.url.path == '/api/launcher/modules') {
          return http.Response('[{"id":"neurocnl"}]', 200);
        }
        if (request.url.path == '/api/launcher/modules/neurocnl') {
          return http.Response('{"status":4}', 200);
        }
        return http.Response('{"status":"ok"}', 200);
      }),
    );

    final snapshot = await service.load();

    expect(snapshot.isReady, isTrue);
    expect(snapshot.activeJob?.stage, 'completed');
  });

  test('completed backend verification updates only the selected Akida host',
      () async {
    final requestedPaths = <String>[];
    final service = ClientDeploymentService(
      persistenceFactory: _completedRemotePersistence,
      httpClient: MockClient((request) async {
        requestedPaths.add('${request.method} ${request.url.path}');
        if (request.method == 'POST' &&
            request.url.path == '/api/launcher/modules/neurocnl/start') {
          return http.Response('{}', 202);
        }
        if (request.url.path == '/api/launcher/modules') {
          return http.Response('[{"id":"neurocnl"}]', 200);
        }
        if (request.url.path == '/api/launcher/modules/neurocnl') {
          return http.Response('{"status":4}', 200);
        }
        if (request.url.path == '/api/launcher/settings') {
          return http.Response(
            '{"selectedAkidaHostId":"selected-host"}',
            200,
          );
        }
        if (request.url.path.endsWith('/runtime-update-jobs')) {
          return http.Response(
            '{"jobId":"runtime-job","status":"completed",'
            '"installedVersion":"0.6.0"}',
            202,
          );
        }
        return http.Response('{"status":"ok"}', 200);
      }),
    );

    final snapshot = await service.load();

    expect(snapshot.isReady, isTrue);
    expect(snapshot.activeJob?.error, isEmpty);
    expect(
      requestedPaths,
      contains(
        'POST /api/launcher/akida/hosts/selected-host/runtime-update-jobs',
      ),
    );
    expect(
      requestedPaths.where((path) => path.contains('other-host')),
      isEmpty,
    );
  });

  test('Akida update failure is degraded and preserves core readiness',
      () async {
    final service = ClientDeploymentService(
      persistenceFactory: _completedRemotePersistence,
      httpClient: MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/api/launcher/modules/neurocnl/start') {
          return http.Response('{}', 202);
        }
        if (request.url.path == '/api/launcher/modules') {
          return http.Response('[{"id":"neurocnl"}]', 200);
        }
        if (request.url.path == '/api/launcher/modules/neurocnl') {
          return http.Response('{"status":4}', 200);
        }
        if (request.url.path == '/api/launcher/settings') {
          return http.Response(
            '{"selectedAkidaHostId":"selected-host"}',
            200,
          );
        }
        if (request.url.path.endsWith('/runtime-update-jobs')) {
          return http.Response(
            '{"jobId":"runtime-job","status":"failed",'
            '"message":"The selected Akida host is offline.",'
            '"recovery":"Power it on, then retry."}',
            202,
          );
        }
        return http.Response('{"status":"ok"}', 200);
      }),
    );

    final snapshot = await service.load();

    expect(snapshot.isReady, isTrue);
    expect(snapshot.activeJob?.stage, 'completed');
    expect(
      snapshot.activeJob?.error,
      startsWith('degraded optional capability:'),
    );
    expect(snapshot.activeJob?.error, contains('Akida'));
    expect(snapshot.activeJob?.error, contains('Power it on, then retry.'));
  });

  test('Akida ready never hides a failed backend', () async {
    final service = ClientDeploymentService(
      persistenceFactory: _completedRemotePersistence,
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/suite/doctor') {
          throw http.ClientException('backend down');
        }
        if (request.url.path == '/api/launcher/doctor') {
          return http.Response(
            '{"fatalCount":0,"degradedCount":0,'
            '"akidaHosts":[{"id":"akida-1","state":"ready"}]}',
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );

    final report = await service.diagnoseTarget('remote');

    expect(report.overall, SystemHealthStatus.failed);
    expect(
      report.checks.singleWhere((check) => check.id == 'suite-api').status,
      SystemHealthStatus.failed,
    );
    expect(
      report.checks.singleWhere((check) => check.id == 'akida-runtime').status,
      SystemHealthStatus.ok,
    );
  });
}
