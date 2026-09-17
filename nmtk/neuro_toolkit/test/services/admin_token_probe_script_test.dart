import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/deployment/remote_deployment_runner.dart';

import 'deployment/client_deployment_test_fakes.dart';

/// Linking credentials to a server that is already running must recover the
/// administrator token that server actually uses. An abandoned install leaves
/// a stale token behind in the login account, so the probe has to verify a
/// candidate against the live launcher before accepting it.
({int exitCode, String stdout}) _runProbe({
  required String deployAccountToken,
  required String loginAccountToken,
  required String acceptedToken,
  String acceptedCode = '200',
}) {
  final fixture = Directory.systemTemp.createTempSync('nmtk-admin-token-');
  addTearDown(() => fixture.deleteSync(recursive: true));
  final bin = Directory('${fixture.path}/bin')..createSync();

  void writeToken(String dir, String token) {
    if (token.isEmpty) return;
    final credentials = Directory('$dir/credentials')
      ..createSync(recursive: true);
    File('${credentials.path}/admin-token').writeAsStringSync(token);
  }

  final deployHome = '${fixture.path}/deploy-home';
  final loginDeployDir = '${fixture.path}/login-home/.nmtk/deploy';
  writeToken('$deployHome/.nmtk/deploy', deployAccountToken);
  writeToken(loginDeployDir, loginAccountToken);

  writeExecutable(
    bin,
    'getent',
    '#!/bin/bash\n'
        '[[ "\$1" == "passwd" && "\$2" == "nmtk-deploy" ]] || exit 1\n'
        'printf "nmtk-deploy:x:1001:1001::%s:/bin/bash\\n" '
        '"\$NMTK_DEPLOY_HOME"\n',
  );
  // Answers 200 only for the token the running backend was started with.
  writeExecutable(
    bin,
    'curl',
    '#!/bin/bash\n'
        'token=""\n'
        'while [[ \$# -gt 0 ]]; do\n'
        '  if [[ "\$1" == "-H" ]]; then token="\${2#X-NMTK-Admin-Token: }"; fi\n'
        '  shift\n'
        'done\n'
        'if [[ "\$token" == "\$NMTK_ACCEPTED_TOKEN" ]]; then '
        'echo -n "\$NMTK_ACCEPTED_CODE"\n'
        'else echo -n 401\n'
        'fi\n',
  );

  final script = File('${fixture.path}/probe.sh')
    ..writeAsStringSync(
      buildAdminTokenProbeScript(
        loginDeployDir: loginDeployDir,
        backendPort: 9000,
      ),
    );
  final result = Process.runSync(
    'bash',
    [script.path],
    environment: {
      'PATH': '${bin.path}:/usr/bin:/bin',
      'NMTK_DEPLOY_HOME': deployHome,
      'NMTK_ACCEPTED_TOKEN': acceptedToken,
      'NMTK_ACCEPTED_CODE': acceptedCode,
    },
  );
  return (
    exitCode: result.exitCode,
    stdout: (result.stdout as String).trim(),
  );
}

void main() {
  test('adopts the running backend\'s token from the deployment account', () {
    final probe = _runProbe(
      deployAccountToken: 'live-token',
      loginAccountToken: '',
      acceptedToken: 'live-token',
    );
    expect(probe.exitCode, 0);
    expect(probe.stdout, 'NMTK_ADMIN_TOKEN|live-token');
  });

  test('skips a stale token an abandoned install left behind', () {
    final probe = _runProbe(
      deployAccountToken: 'live-token',
      loginAccountToken: 'abandoned-install-token',
      acceptedToken: 'live-token',
    );
    expect(probe.stdout, 'NMTK_ADMIN_TOKEN|live-token');
  });

  test('accepts a token the backend authenticates on an unmounted route', () {
    // suite_api protects every route but /api/suite/health, so a valid token
    // on a route this deployment does not mount answers 404. That still
    // proves the credential; only 401/403 mean it was rejected.
    final probe = _runProbe(
      deployAccountToken: 'live-token',
      loginAccountToken: '',
      acceptedToken: 'live-token',
      acceptedCode: '404',
    );
    expect(probe.exitCode, 0);
    expect(probe.stdout, 'NMTK_ADMIN_TOKEN|live-token');
  });

  test('reports nothing when no readable token is accepted', () {
    final probe = _runProbe(
      deployAccountToken: '',
      loginAccountToken: 'abandoned-install-token',
      acceptedToken: 'live-token',
    );
    expect(probe.exitCode, 1);
    expect(probe.stdout, isEmpty);
  });
}
