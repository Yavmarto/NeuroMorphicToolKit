import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/deployment/remote_bootstrap_script.dart';

import 'deployment/client_deployment_test_fakes.dart';

({Directory fixture, ProcessResult result, String commandLog})
_runDeploymentCredentialFixture({bool failKeyGeneration = false}) {
  final fixture = Directory.systemTemp.createTempSync(
    'nmtk-deployment-credential-',
  );
  final bin = Directory('${fixture.path}/bin')..createSync();
  final deployHome = Directory('${fixture.path}/deploy-home')..createSync();
  final commandLog = File('${fixture.path}/commands.log');

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
    'id',
    '#!/bin/bash\n'
        'if [[ "\$1" == "-u" && \$# -eq 1 ]]; then echo 0; exit 0; fi\n'
        // `id -un` names the administrator account that ran setup, which the
        // bootstrap adds to the deployment group so it can read the admin
        // token later. This fixture runs the script as root.
        'if [[ "\$1" == "-un" && \$# -eq 1 ]]; then echo root; exit 0; fi\n'
        'if [[ "\$1" == "-u" ]]; then echo 48333; exit 0; fi\n'
        '[[ "\$1" == "nmtk-deploy" ]] && exit 0\n'
        'exit 1\n',
  );
  writeExecutable(
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
  writeExecutable(bin, 'usermod', '#!/bin/bash\nexit 0\n');
  writeExecutable(
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
  writeExecutable(
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

  final completeScript = buildRemoteBootstrapScript(
    containerEngine: 'docker',
    factoryReset: false,
  );
  final preflightIndex = completeScript.indexOf('\nphase "preflight_running"');
  final accountIndex = completeScript.indexOf('\nphase "bootstrapping_access"');
  final credentialScript =
      '${completeScript.substring(0, preflightIndex)}'
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

void main() {
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
    final fixture = _runDeploymentCredentialFixture(failKeyGeneration: true);
    addTearDown(() {
      if (fixture.fixture.existsSync()) {
        fixture.fixture.deleteSync(recursive: true);
      }
    });
    final combinedOutput = '${fixture.result.stdout}\n${fixture.result.stderr}';

    expect(fixture.result.exitCode, 26, reason: combinedOutput);
    expect(combinedOutput, contains('NMTK_SETUP_COMMAND_EXIT|exit|42'));
    final keyPath = RegExp(
      r'key-path (/[^\s]+)',
    ).firstMatch(fixture.commandLog)?.group(1);
    expect(keyPath, isNotNull);
    expect(Directory(File(keyPath!).parent.path).existsSync(), isFalse);
  });
}
