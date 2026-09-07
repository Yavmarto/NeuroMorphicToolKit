import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/server/provision/provision_notifier.dart';
import 'package:neuro_toolkit/features/server/provision/provision_service.dart';
import 'package:neuro_toolkit/screens/server_setup_screen.dart';

/// Functional stand-in that drives [provisionNotifierProvider] through the
/// exact state transitions the real notifier produces: idle → running (with
/// plain-English phase labels) → done, or → failed.
class _FakeProvisionNotifier extends ProvisionNotifier {
  _FakeProvisionNotifier(this.behavior);

  final String behavior; // 'success' | 'failure'

  int provisionCalls = 0;
  String? lastHost;
  String? lastSudoUser;
  String? lastPassword;
  String? lastPrivateKey;
  String? lastEngine;

  @override
  ProvisionState build() => const ProvisionState();

  @override
  Future<void> provision(ProvisionRequest request) async {
    provisionCalls++;
    lastHost = request.host;
    lastSudoUser = request.sudoUser;
    lastPassword = request.credential.password;
    lastPrivateKey = request.credential.privateKey;
    lastEngine = request.engine;

    state = const ProvisionState(
      isRunning: true,
      phaseLabel: 'Connecting with administrator access',
      progress: 0.2,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    state = const ProvisionState(
      isRunning: true,
      phaseLabel: 'Bootstrapping deployment account',
      progress: 0.6,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (behavior == 'failure') {
      state = const ProvisionState(
        failure: ProvisionFailure(
          cause:
              'The administrator password or key was not accepted. Check it '
              'and try again.',
        ),
      );
    } else {
      state = ProvisionState(result: ProvisionResult(host: request.host));
    }
  }
}

Widget _host({required _FakeProvisionNotifier notifier}) {
  return ProviderScope(
    overrides: [
      provisionNotifierProvider.overrideWith(() => notifier),
    ],
    child: const MaterialApp(home: ServerSetupScreen()),
  );
}

void main() {
  testWidgets('provision form collects host, admin, credential and engine',
      (tester) async {
    final notifier = _FakeProvisionNotifier('success');
    await tester.pumpWidget(_host(notifier: notifier));

    expect(find.text('Set up your server'), findsOneWidget);
    expect(find.text('Server address'), findsWidgets);
    expect(find.text('Administrator account'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Docker'), findsOneWidget);
    expect(find.text('Podman'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('server-setup-host')),
      '192.168.2.90',
    );
    await tester.enterText(
      find.byKey(const Key('server-setup-username')),
      'moosebun2',
    );
    await tester.enterText(
      find.byKey(const Key('server-setup-password')),
      'correct horse',
    );
    await tester.ensureVisible(find.byKey(const Key('server-setup-provision')));
    await tester.tap(find.byKey(const Key('server-setup-provision')));
    await tester.pumpAndSettle();

    expect(notifier.provisionCalls, 1);
    expect(notifier.lastHost, '192.168.2.90');
    expect(notifier.lastSudoUser, 'moosebun2');
    expect(notifier.lastPassword, 'correct horse');
    expect(notifier.lastEngine, 'docker');
  });

  testWidgets('progress panel shows plain-English phase updates while running',
      (tester) async {
    final notifier = _FakeProvisionNotifier('success');
    await tester.pumpWidget(_host(notifier: notifier));

    await tester.enterText(
      find.byKey(const Key('server-setup-host')),
      '192.168.2.90',
    );
    await tester.enterText(
      find.byKey(const Key('server-setup-username')),
      'moosebun2',
    );
    await tester.enterText(
      find.byKey(const Key('server-setup-password')),
      'secret',
    );
    await tester.ensureVisible(find.byKey(const Key('server-setup-provision')));
    await tester.tap(find.byKey(const Key('server-setup-provision')));
    await tester.pump();

    expect(find.byKey(const Key('server-setup-progress')), findsOneWidget);
    // "Connecting with administrator access" is mapped to plain English.
    expect(find.text('Connecting to your server…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 60));
    expect(
      find.text('Preparing the account that runs your server…'),
      findsOneWidget,
    );

    await tester.pumpAndSettle();
  });

  testWidgets('failure shows a plain-English cause and a retry that re-runs',
      (tester) async {
    final notifier = _FakeProvisionNotifier('failure');
    await tester.pumpWidget(_host(notifier: notifier));

    await tester.enterText(
      find.byKey(const Key('server-setup-host')),
      '192.168.2.90',
    );
    await tester.enterText(
      find.byKey(const Key('server-setup-username')),
      'moosebun2',
    );
    await tester.enterText(
      find.byKey(const Key('server-setup-password')),
      'secret',
    );
    await tester.ensureVisible(find.byKey(const Key('server-setup-provision')));
    await tester.tap(find.byKey(const Key('server-setup-provision')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('server-setup-failure')), findsOneWidget);
    expect(
      find.textContaining('was not accepted'),
      findsWidgets,
    );
    // No SSH / sudo / docker / jargon leaks into the failure copy.
    for (final word in const ['SSH', 'sudo', 'docker', 'exit code', 'stderr']) {
      expect(find.textContaining(word), findsNothing);
    }

    // Retry must actually re-invoke the provision call, not be a dead button.
    await tester.ensureVisible(find.byKey(const Key('server-setup-retry')));
    await tester.tap(find.byKey(const Key('server-setup-retry')));
    await tester.pumpAndSettle();
    expect(notifier.provisionCalls, 2);
  });

  testWidgets('success shows the provisioned host and a continue action',
      (tester) async {
    final notifier = _FakeProvisionNotifier('success');
    var continued = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          provisionNotifierProvider.overrideWith(() => notifier),
        ],
        child: MaterialApp(
          home: ServerSetupScreen(
            onProvisioned: (_) => continued = true,
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('server-setup-host')),
      '192.168.2.90',
    );
    await tester.enterText(
      find.byKey(const Key('server-setup-username')),
      'moosebun2',
    );
    await tester.enterText(
      find.byKey(const Key('server-setup-password')),
      'secret',
    );
    await tester.ensureVisible(find.byKey(const Key('server-setup-provision')));
    await tester.tap(find.byKey(const Key('server-setup-provision')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('server-setup-success')), findsOneWidget);
    expect(find.textContaining('192.168.2.90'), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('server-setup-continue')));
    await tester.tap(find.byKey(const Key('server-setup-continue')));
    expect(continued, isTrue);
  });

  testWidgets('form validation rejects a blank address without calling the API',
      (tester) async {
    final notifier = _FakeProvisionNotifier('success');
    await tester.pumpWidget(_host(notifier: notifier));

    await tester.ensureVisible(find.byKey(const Key('server-setup-provision')));
    await tester.tap(find.byKey(const Key('server-setup-provision')));
    await tester.pumpAndSettle();

    expect(notifier.provisionCalls, 0);
    expect(
      find.textContaining('Enter the server address'),
      findsWidgets,
    );
  });

  testWidgets('provision rejects root as the administrator account',
      (tester) async {
    final notifier = _FakeProvisionNotifier('success');
    await tester.pumpWidget(_host(notifier: notifier));

    await tester.enterText(
      find.byKey(const Key('server-setup-host')),
      '192.168.2.90',
    );
    await tester.enterText(
      find.byKey(const Key('server-setup-username')),
      'root',
    );
    await tester.enterText(
      find.byKey(const Key('server-setup-password')),
      'secret',
    );
    await tester.ensureVisible(find.byKey(const Key('server-setup-provision')));
    await tester.tap(find.byKey(const Key('server-setup-provision')));
    await tester.pumpAndSettle();

    expect(notifier.provisionCalls, 0);
    expect(
      find.textContaining('not root'),
      findsWidgets,
    );
  });
}
