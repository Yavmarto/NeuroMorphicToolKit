import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/deployment/remote_bootstrap_script.dart';

import 'deployment/client_deployment_test_fakes.dart';

({
  ProcessResult result,
  String commandLog,
  String dormantUser,
  String skippedUser,
})
_runRootlessReconciliationFixture({
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
  Directory(
    '${dormantHome.path}/.local/share/containers/storage',
  ).createSync(recursive: true);
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
    Directory(
      '${runtimeBase.path}/$dormantUid/libpod',
    ).createSync(recursive: true);
  }

  writeExecutable(bin, 'id', '#!/bin/bash\necho 0\n');
  writeExecutable(bin, 'uname', '#!/bin/bash\necho Linux\n');
  writeExecutable(
    bin,
    'df',
    '#!/bin/bash\n'
        "printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\n'\n"
        "printf '/dev/fake 20000000 1 19999999 1%% /\\n'\n",
  );
  writeExecutable(
    bin,
    'timeout',
    '#!/bin/bash\n'
        'while [[ "\$1" == --* ]]; do shift; done\n'
        'shift\n'
        'exec "\$@"\n',
  );
  writeExecutable(
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
  writeExecutable(
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
  writeExecutable(
    bin,
    'chown',
    '#!/bin/bash\n'
        'printf "chown %s\\n" "\$*" >>"\$NMTK_FAKE_LOG"\n',
  );
  writeExecutable(
    bin,
    'stat',
    '#!/bin/bash\n'
        'echo ${unsafeActiveRuntime ? 99999 : dormantUid}\n',
  );
  if (failRuntimeCleanup) {
    writeExecutable(
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

  final completeScript = buildRemoteBootstrapScript(
    containerEngine: 'podman',
    factoryReset: factoryReset,
  ).replaceFirst('done </etc/passwd', 'done <"${passwd.path}"');
  final installPhase = completeScript.indexOf(
    '\nphase "installing_prerequisites"',
  );
  final reconciliationScript =
      '${completeScript.substring(0, installPhase)}\n'
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

void main() {
  test(
    'dormant Podman user gets a temporary runtime while unrelated users are skipped',
    () {
      final fixture = _runRootlessReconciliationFixture();
      final combinedOutput =
          '${fixture.result.stdout}\n${fixture.result.stderr}';

      expect(fixture.result.exitCode, 0, reason: combinedOutput);
      expect(
        combinedOutput,
        contains('NMTK_SETUP_COMMAND|runuser -u ${fixture.dormantUser} -- env'),
      );
      expect(combinedOutput, contains('podman info'));
      expect(fixture.commandLog, contains('runuser -u ${fixture.dormantUser}'));
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
    },
  );

  test(
    'valid stale container IDs are removed but malformed IDs are rejected',
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
      expect(malformed.commandLog, isNot(contains('podman rm -f time=')));
    },
  );

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

  test('privilege drops do not inherit the administrator home directory', () {
    final script = buildRemoteBootstrapScript(
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
    final fixture = _runRootlessReconciliationFixture(failRuntimeCleanup: true);
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
}
