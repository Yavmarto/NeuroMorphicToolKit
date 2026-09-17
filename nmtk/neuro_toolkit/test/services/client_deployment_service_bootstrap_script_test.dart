import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/deployment/bootstrap_transcript_parsing.dart';
import 'package:neuro_toolkit/services/deployment/client_deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/deployment_persistence.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/remote_bootstrap_script.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deployment/client_deployment_test_fakes.dart';

void main() {
  test(
    'remote bootstrap reconciles both runtimes without broad sudo access',
    () {
      final script = buildRemoteBootstrapScript(
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
      expect(script, isNot(contains('mktemp /tmp/nmtk-deploy-key.XXXXXX')));
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
      expect(administratorShellCommand(needsSudo: false), 'bash');
      expect(administratorShellCommand(needsSudo: true), 'sudo -S -p "" bash');
    },
  );

  test(
    'bootstrap failure markers produce actionable sanitized diagnostics',
    () {
      final details = parseBootstrapFailureForTesting(
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
      expect(
        details.technicalDetails,
        isNot(contains('temporary-admin-secret')),
      );
      expect(details.technicalDetails, contains('[redacted]'));
    },
  );

  test(
    'a responding command that never exits is terminated as a process group',
    () {
      final completeScript = buildRemoteBootstrapScript(
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
        contains('NMTK_SETUP_STEP|start|1|false|systemctl --user enable'),
      );
      expect(
        output,
        contains('NMTK_SETUP_STEP|finish|1|false|systemctl --user enable'),
      );
      expect(output, contains('NMTK_SETUP_COMMAND_EXIT|timeout|1'));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 6)));
      expect(completeScript, isNot(contains('timeout --foreground')));
    },
  );

  test(
    'a successful command cannot leave transcript pipes open through a child',
    () {
      final completeScript = buildRemoteBootstrapScript(
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
      expect(output, contains('NMTK_SETUP_STEP|start|5|false|podman info'));
      expect(output, contains('NMTK_SETUP_STEP|finish|5|false|podman info'));
      expect(output, contains('NMTK_SETUP_TERMINAL|capture returned'));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 6)));
    },
  );

  test(
    'an escaped writer cannot outlive the transcript drain deadline',
    () async {
      final setsidResult = Process.runSync('sh', const [
        '-c',
        'command -v setsid',
      ]);
      if (setsidResult.exitCode != 0) return;
      final setsidPath = setsidResult.stdout.toString().trim();
      final completeScript = buildRemoteBootstrapScript(
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
          final escapedPid = int.tryParse(
            escapedPidFile.readAsStringSync().trim(),
          );
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
      for (
        var attempt = 0;
        attempt < 25 && !escapedPidFile.existsSync();
        attempt += 1
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(escapedPidFile.existsSync(), isTrue, reason: output);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 6)));
    },
  );

  test('fallback Podman service detaches without transcript descriptors', () {
    final script = buildRemoteBootstrapScript(
      containerEngine: 'podman',
      factoryReset: false,
    );

    expect(script, contains('setsid -f podman system service --time=0'));
    expect(script, contains('podman --remote --url "\$remote_url" info'));
    expect(
      script,
      contains('</dev/null >"\$HOME/.nmtk-podman-service.log" 2>&1'),
    );
    expect(script, isNot(contains('nohup podman system service')));
    expect(script, contains('setsid is required'));
  });

  test(
    'unknown bootstrap failures retain bounded output without credentials',
    () {
      final details = parseBootstrapFailureForTesting(
        '${List<String>.filled(9000, 'x').join()}\nadmin-private-key',
        exitCode: 2,
        rootPrivateKey: 'admin-private-key',
      );

      expect(details.code, 'unknown_bootstrap_failure');
      expect(details.technicalDetails, startsWith('… output truncated …'));
      expect(details.technicalDetails.length, lessThanOrEqualTo(8030));
      expect(details.technicalDetails, isNot(contains('admin-private-key')));
    },
  );

  test(
    'bootstrap transcript exposes raw output and hides protocol markers',
    () {
      expect(
        parseBootstrapTranscriptLineForTesting(
          r'NMTK_SETUP_COMMAND|podman info',
        ),
        r'$ podman info',
      );
      expect(
        parseBootstrapTranscriptLineForTesting('host: amd64'),
        'host: amd64',
      );
      expect(
        parseBootstrapTranscriptLineForTesting(
          'NMTK_SETUP_TERMINAL|✓ Podman is accessible',
        ),
        isNull,
      );
      expect(
        parseBootstrapTranscriptLineForTesting(
          'NMTK_SETUP_PHASE|preflight_running|7|Checking server',
        ),
        isNull,
      );
      expect(
        parseBootstrapTranscriptLineForTesting(
          'NMTK_SETUP_STEP|start|20|true|Verifying rootless Podman API',
        ),
        isNull,
      );
      expect(
        parseBootstrapTranscriptLineForTesting(
          'NMTK_DEPLOY_PRIVATE_KEY_B64=cHJpdmF0ZQ==',
        ),
        isNull,
      );
      expect(
        parseBootstrapTranscriptLineForTesting(
          'password=temporary-secret \x1b[31mfailed\x1b[0m',
          rootPassword: 'temporary-secret',
        ),
        'password=[redacted] failed',
      );
      expect(
        parseBootstrapTranscriptLineForTesting(
          'NMTK_SETUP_COMMAND_EXIT|exit|125',
        ),
        '[client: command exited 125]',
      );
    },
  );

  test('bootstrap operation markers contain only safe progress metadata', () {
    final started = parseBootstrapOperationMarkerForTesting(
      'NMTK_SETUP_STEP|start|20|true|Verifying rootless Podman API',
    );
    final finished = parseBootstrapOperationMarkerForTesting(
      'NMTK_SETUP_STEP|finish|20|true|Verifying rootless Podman API',
    );

    expect(started?.state, 'start');
    expect(started?.timeoutSeconds, 20);
    expect(started?.automaticRecovery, isTrue);
    expect(started?.label, 'Verifying rootless Podman API');
    expect(finished?.state, 'finish');
    expect(
      parseBootstrapOperationMarkerForTesting(
        'NMTK_SETUP_STEP|start|20|true|password=secret|extra',
      ),
      isNull,
    );
  });

  test('client watchdog failures are structured and retryable', () {
    final details = administratorStepTimeoutForTesting(
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
    final details = administratorStallForTesting(phase: 'bootstrapping_access');

    expect(details.code, 'administrator_stalled');
    expect(details.phase, 'bootstrapping_access');
    expect(details.summary, 'The server stopped reporting progress');
    expect(details.recovery, contains('Select Retry'));
    expect(details.exitCode, 124);
  });

  test('the administrator script announces its own exit on every path', () {
    final completeScript = buildRemoteBootstrapScript(
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
    expect('${successResult.stdout}', contains('NMTK_SETUP_DONE|0'));

    final failure = File('${fixture.path}/failure.sh')
      ..writeAsStringSync(
        '$prologue\nfail "deploy_account_failed" 25 "no account"\n',
      );
    final failureResult = Process.runSync('bash', [failure.path]);
    expect(failureResult.exitCode, 25);
    expect('${failureResult.stdout}', contains('NMTK_SETUP_DONE|25'));

    // The marker is protocol, not transcript: it must never reach the raw SSH
    // output the user reads.
    expect(parseBootstrapTranscriptLineForTesting('NMTK_SETUP_DONE|0'), isNull);
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

    await drainTranscriptStreamsForTesting(
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

    await settleStreamedUpdatesForTesting(
      wedged.future,
      timeout: const Duration(milliseconds: 50),
    ).timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('settling a wedged progress write never returned'),
    );
  });

  test('terminal output bounds and replaces the remote install section', () {
    final bounded = boundTerminalOutputForTesting(
      List<String>.generate(2100, (index) => 'server output $index'),
    );
    expect(bounded.length, lessThanOrEqualTo(2000));
    expect(bounded.first, '[client: earlier SSH output truncated]');
    expect(bounded.last, 'server output 2099');

    final first = replaceRemoteInstallOutputForTesting(
      const <String>[r'$ uname -s', 'Linux'],
      const <String>['pulling image layer 1'],
    );
    final second = replaceRemoteInstallOutputForTesting(first, const <String>[
      'pulling image layer 1',
      'pulling image layer 2',
    ]);
    expect(
      second.where((line) => line == 'pulling image layer 1'),
      hasLength(1),
    );
    expect(second, contains('pulling image layer 2'));
  });

  test(
    'remote setup creates a persisted job before SSH bootstrap completes',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final secrets = MemorySecretStorage();
      final persistence = DeploymentPersistence(
        preferences: await SharedPreferences.getInstance(),
        secureStorage: secrets,
      );
      final service = ClientDeploymentService(
        assets: ManifestAssetBundle(),
        persistenceFactory: () async => persistence,
        ssh: BlockingSshDeploymentService(),
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
        secrets.values.toString(),
        isNot(contains('temporary-admin-secret')),
      );
    },
  );

  test('factory reset is the only bootstrap mode that removes volumes', () {
    final preserve = buildRemoteBootstrapScript(
      containerEngine: 'podman',
      factoryReset: false,
    );
    final reset = buildRemoteBootstrapScript(
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
        buildRemoteBootstrapScript(
          containerEngine: 'docker',
          factoryReset: false,
        ),
      );

    final result = Process.runSync('bash', ['-n', scriptFile.path]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
  });
}
