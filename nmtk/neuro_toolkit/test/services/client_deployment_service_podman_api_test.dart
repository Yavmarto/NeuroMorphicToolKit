import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/deployment/bootstrap_transcript_parsing.dart';
import 'package:neuro_toolkit/services/deployment/remote_bootstrap_script.dart';

import 'deployment/client_deployment_test_fakes.dart';

({ProcessResult result, String commandLog}) _runPodmanApiProvisioningFixture({
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
    'runuser',
    '#!/bin/bash\n'
        'while [[ "\$1" != "--" ]]; do shift; done\n'
        'shift\n'
        'exec "\$@"\n',
  );
  writeExecutable(
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
        "s.bind(sys.argv[1]); s.listen(1)' "
        '"\$NMTK_SOCKET" >/dev/null 2>&1\n'
        "    python3 -c 'import time; time.sleep(10)' >/dev/null 2>&1 &\n"
        '    printf "%s\\n" "\$!" >"\$NMTK_SERVICE_PID"\n'
        '  fi\n'
        '  exit "\$NMTK_SYSTEMCTL_START_EXIT"\n'
        'fi\n'
        'exit 0\n',
  );
  writeExecutable(
    bin,
    'setsid',
    '#!/bin/bash\n'
        'printf "fallback %s\\n" "\$*" >>"\$NMTK_FAKE_LOG"\n'
        'touch "\$NMTK_FALLBACK_MARKER"\n'
        '[[ "\$NMTK_FALLBACK_CREATES_SOCKET" == "true" ]] || exit 1\n'
        "python3 -c 'import socket,sys; "
        's=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); '
        "s.listen(1)' "
        '"\$NMTK_SOCKET" >/dev/null 2>&1\n'
        "python3 -c 'import time; time.sleep(10)' >/dev/null 2>&1 &\n"
        'printf "%s\\n" "\$!" >"\$NMTK_SERVICE_PID"\n',
  );
  writeExecutable(
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

  final completeScript = buildRemoteBootstrapScript(
    containerEngine: 'podman',
    factoryReset: false,
  );
  final preflightIndex = completeScript.indexOf('\nif [ "\$(id -u)"');
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
  final provisioningScript =
      '${completeScript.substring(0, preflightIndex)}\n'
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

void main() {
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
        fixture.commandLog,
        contains('systemctl --user start podman.socket'),
      );
      expect(fixture.commandLog, contains('fallback -f podman system service'));
      expect(fixture.commandLog, contains('podman --remote --url unix://'));
      expect(
        output,
        contains(
          'NMTK_SETUP_STEP|start|30|true|'
          'Starting or repairing rootless Podman API',
        ),
      );
      expect(output, contains('✓ Podman API fixture completed'));
    },
  );

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
    expect(output, isNot(contains('NMTK_SETUP_ERROR|deploy_account_failed|')));
  });

  test('a delayed healthy systemd Podman socket avoids fallback startup', () {
    final fixture = _runPodmanApiProvisioningFixture(
      systemctlCreatesSocket: true,
    );
    final output = '${fixture.result.stdout}\n${fixture.result.stderr}';

    expect(fixture.result.exitCode, 0, reason: output);
    expect(
      fixture.commandLog,
      contains('systemctl --user start podman.socket'),
    );
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
    expect(output, contains('NMTK_SETUP_ERROR|podman_api_start_failed|'));
    expect(output, isNot(contains('NMTK_DEPLOY_PRIVATE_KEY_B64=')));

    final details = parseBootstrapFailureForTesting(
      output,
      exitCode: fixture.result.exitCode,
    );
    expect(details.summary, 'The Podman service could not be started');
    expect(details.recovery, contains('Restart the server'));
    expect(details.recovery, contains('Set up and connect'));
  });
}
