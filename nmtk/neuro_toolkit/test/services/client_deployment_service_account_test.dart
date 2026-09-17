import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/deployment/bootstrap_transcript_parsing.dart';
import 'package:neuro_toolkit/services/deployment/remote_bootstrap_script.dart';

import 'deployment/client_deployment_test_fakes.dart';

({Directory fixture, List<ProcessResult> results, String commandLog})
_runDeploymentAccountFixture({
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
  writeExecutable(
    bin,
    'id',
    '#!/bin/bash\n'
        'if [[ "\$1" == "-u" && \$# -eq 1 ]]; then echo 0; exit 0; fi\n'
        // `id -un` names the administrator account that ran setup, which the
        // bootstrap adds to the deployment group so it can read the admin
        // token later. This fixture runs the script as root.
        'if [[ "\$1" == "-un" && \$# -eq 1 ]]; then echo root; exit 0; fi\n'
        '[[ "\${!#}" == "nmtk-deploy" && '
        '-f "\$NMTK_USER_STATE" ]] || exit 1\n'
        '[[ "\$1" == "-u" ]] && echo 48333\n'
        'exit 0\n',
  );
  writeExecutable(
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
  writeExecutable(
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
  writeExecutable(
    bin,
    'usermod',
    '#!/bin/bash\n'
        'printf "usermod %s\\n" "\$*" >>"\$NMTK_FAKE_LOG"\n'
        '[[ -f "\$NMTK_GROUP_STATE" && -f "\$NMTK_USER_STATE" ]] || exit 6\n'
        // Two grants are legitimate: the deployment account's own primary
        // group, and adding the administrator who ran setup to that group so
        // it can read the admin token afterwards.
        'case " \$* " in\n'
        '  *" --gid nmtk-deploy nmtk-deploy "*) ;;\n'
        '  *" -aG nmtk-deploy "*) ;;\n'
        '  *) exit 65 ;;\n'
        'esac\n',
  );
  writeExecutable(
    bin,
    'rm',
    '#!/bin/bash\n'
        'if [[ "\$*" == *"/etc/sudoers.d/nmtk-deploy"* ]]; then\n'
        '  printf "rm %s\\n" "\$*" >>"\$NMTK_FAKE_LOG"\n'
        '  exit 0\n'
        'fi\n'
        'exec /bin/rm "\$@"\n',
  );
  writeExecutable(
    bin,
    'install',
    '#!/bin/bash\n'
        'printf "install %s\\n" "\$*" >>"\$NMTK_FAKE_LOG"\n'
        '[[ "\$1" == "-d" ]] || exit 0\n'
        'mkdir -p "\${!#}"\n',
  );

  final completeScript = buildRemoteBootstrapScript(
    containerEngine: 'docker',
    factoryReset: false,
  );
  final preflightIndex = completeScript.indexOf('\nphase "preflight_running"');
  final accountIndex = completeScript.indexOf('\nphase "bootstrapping_access"');
  final credentialIndex = completeScript.indexOf(
    '\ncapture_step 30 "deploy_account_failed" 26 \\\n'
    '  "Preparing deployment credential workspace"',
    accountIndex,
  );
  final accountScript =
      '${completeScript.substring(0, preflightIndex)}'
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
          'NMTK_DEPLOY_HOME': invalidHome
              ? 'relative/deploy-home'
              : deployHome.path,
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

void main() {
  test(
    'deployment account reconciliation is idempotent for every partial state',
    () {
      final cases =
          <
            ({
              String name,
              bool userExists,
              bool groupExists,
              int groupAdds,
              int userAdds,
              int userMods,
            })
          >[
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
          RegExp(
            r'^groupadd ',
            multiLine: true,
          ).allMatches(fixture.commandLog).length,
          testCase.groupAdds,
          reason: testCase.name,
        );
        expect(
          RegExp(
            r'^useradd ',
            multiLine: true,
          ).allMatches(fixture.commandLog).length,
          testCase.userAdds,
          reason: testCase.name,
        );
        // Only the deployment account's own primary-group reconciliation is
        // counted here; the administrator grant below is a separate, additive
        // call that runs every time.
        expect(
          RegExp(
            r'^usermod --gid ',
            multiLine: true,
          ).allMatches(fixture.commandLog).length,
          testCase.userMods,
          reason: testCase.name,
        );
        // `usermod -aG` is additive, so re-running it is safe — and repeating
        // it is what stops a re-run from leaving the administrator without the
        // group membership it needs to read the admin token.
        expect(
          RegExp(
            r'^usermod -aG nmtk-deploy ',
            multiLine: true,
          ).allMatches(fixture.commandLog).length,
          2,
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
    },
  );

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
    final details = parseBootstrapFailureForTesting(
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
    expect(details.technicalDetails, isNot(contains('temporary-admin-secret')));
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
}
