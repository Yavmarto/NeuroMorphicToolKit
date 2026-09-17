import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/server/connect/connect_build_policy.dart';
import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/features/server/connect/connect_service.dart';
import 'package:neuro_toolkit/screens/server_connect_screen.dart';

Key get _connectButtonKey => Key(
  ConnectBuildPolicy.requiresCredentialAuth
      ? 'server-connect-sign-in'
      : 'server-connect-connect',
);

Future<void> _fillConnectForm(
  WidgetTester tester, {
  required String host,
  String username = 'alice',
  String password = 'secret',
}) async {
  await tester.enterText(find.byKey(const Key('server-connect-host')), host);
  if (ConnectBuildPolicy.requiresCredentialAuth) {
    await tester.enterText(
      find.byKey(const Key('server-connect-username')),
      username,
    );
    await tester.enterText(
      find.byKey(const Key('server-connect-password')),
      password,
    );
  }
  await tester.ensureVisible(find.byKey(_connectButtonKey));
  await tester.tap(find.byKey(_connectButtonKey));
}

/// Functional stand-in that drives [connectNotifierProvider] through the exact
/// state transitions the real notifier produces.
class _FakeConnectNotifier extends ConnectNotifier {
  _FakeConnectNotifier(this.behavior, {ConnectState? initialState})
    : _initial = initialState;

  final String behavior; // 'success' | 'failure'
  final ConnectState? _initial;

  int connectCalls = 0;
  int continueWithoutServerCalls = 0;
  ConnectRequest? lastRequest;

  @override
  ConnectState build() => _initial ?? const ConnectState();

  @override
  void continueWithoutServer() {
    continueWithoutServerCalls++;
    state = const ConnectState(phase: ConnectPhase.devOffline);
  }

  @override
  Future<void> connect(ConnectRequest request) async {
    connectCalls++;
    lastRequest = request;
    state = state.copyWith(phase: ConnectPhase.reconnecting);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (behavior == 'failure') {
      state = ConnectState(
        phase: ConnectPhase.failed,
        failureCause: 'Incorrect username or password.',
        savedHost: request.host,
      );
    } else {
      state = ConnectState(
        phase: ConnectPhase.connected,
        session: ConnectSession(
          host: request.host,
          username: request.appUsername,
          sessionToken: 'token',
        ),
        savedHost: request.host,
      );
    }
  }
}

Widget _host({
  required _FakeConnectNotifier notifier,
  bool? showDevBypass,
  VoidCallback? onContinueWithoutServer,
}) {
  return ProviderScope(
    overrides: [connectNotifierProvider.overrideWith(() => notifier)],
    child: MaterialApp(
      home: ServerConnectScreen(
        showDevBypass: showDevBypass ?? true,
        onContinueWithoutServer: onContinueWithoutServer,
      ),
    ),
  );
}

void main() {
  testWidgets('connect form collects the server address', (tester) async {
    final notifier = _FakeConnectNotifier('success');
    await tester.pumpWidget(_host(notifier: notifier));

    expect(
      find.text(
        ConnectBuildPolicy.requiresCredentialAuth
            ? 'Sign in to your server'
            : 'Connect to your server',
      ),
      findsOneWidget,
    );
    expect(find.text('Server address'), findsWidgets);
    if (ConnectBuildPolicy.requiresCredentialAuth) {
      expect(find.text('App account'), findsOneWidget);
      expect(find.text('Password'), findsWidgets);
    } else {
      expect(find.text('App account'), findsNothing);
      expect(find.text('Password'), findsNothing);
    }

    await _fillConnectForm(tester, host: '203.0.113.90');
    await tester.pumpAndSettle();

    expect(notifier.connectCalls, 1);
    expect(notifier.lastRequest?.host, '203.0.113.90');
    if (ConnectBuildPolicy.requiresCredentialAuth) {
      expect(notifier.lastRequest?.appUsername, 'alice');
      expect(notifier.lastRequest?.credential, 'secret');
    }
  });

  testWidgets(
    'connecting to an existing server never asks for an SSH credential',
    (tester) async {
      final notifier = _FakeConnectNotifier('success');
      await tester.pumpWidget(_host(notifier: notifier));

      // Only the app-level connect fields exist; no SSH, key, or
      // admin-credential fields are ever rendered on this screen.
      expect(find.byKey(const Key('server-connect-host')), findsOneWidget);
      if (ConnectBuildPolicy.requiresCredentialAuth) {
        expect(
          find.byKey(const Key('server-connect-username')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('server-connect-password')),
          findsOneWidget,
        );
      }
      for (final word in const ['SSH', 'sudo', 'private key']) {
        expect(find.textContaining(word, findRichText: true), findsNothing);
      }
    },
  );

  testWidgets('pre-fills the saved host from the connect state', (
    tester,
  ) async {
    final notifier = _FakeConnectNotifier(
      'success',
      initialState: const ConnectState(
        phase: ConnectPhase.failed,
        savedHost: '203.0.113.90',
        failureCause: 'Incorrect username or password.',
      ),
    );
    await tester.pumpWidget(_host(notifier: notifier));

    final hostField = tester.widget<NmtkTextInput>(
      find.byKey(const Key('server-connect-host')),
    );
    expect(hostField.controller?.text, '203.0.113.90');
  });

  testWidgets(
    'shows plain-English failure and a retry that re-invokes',
    (tester) async {
      final notifier = _FakeConnectNotifier('failure');
      await tester.pumpWidget(_host(notifier: notifier));

      await _fillConnectForm(tester, host: '203.0.113.90', password: 'wrong');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('server-connect-error')), findsOneWidget);
      expect(
        find.textContaining('Incorrect username or password'),
        findsWidgets,
      );
      for (final word in const [
        'SSH',
        'sudo',
        'docker',
        'stderr',
        'exit code',
      ]) {
        expect(find.textContaining(word), findsNothing);
      }

      // The form is still present, so the user can correct and try again.
      await _fillConnectForm(tester, host: '203.0.113.90', password: 'wrong');
      await tester.pumpAndSettle();
      expect(notifier.connectCalls, 2);
    },
    skip: !ConnectBuildPolicy.requiresCredentialAuth,
  );

  testWidgets(
    'shows a reconnecting panel while the connect call is in flight',
    (tester) async {
      final notifier = _FakeConnectNotifier('success');
      await tester.pumpWidget(_host(notifier: notifier));

      await _fillConnectForm(tester, host: '203.0.113.90');
      await tester.pump();

      expect(
        find.byKey(const Key('server-connect-reconnecting')),
        findsOneWidget,
      );
      expect(find.text('Reconnecting to your server…'), findsOneWidget);

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'form validation rejects a blank address without calling the API',
    (tester) async {
      final notifier = _FakeConnectNotifier('success');
      await tester.pumpWidget(_host(notifier: notifier));

      await tester.ensureVisible(find.byKey(_connectButtonKey));
      await tester.tap(find.byKey(_connectButtonKey));
      await tester.pumpAndSettle();

      expect(notifier.connectCalls, 0);
      expect(find.textContaining('Enter the server address'), findsWidgets);
    },
  );

  testWidgets(
    'shows dev bypass button and allows continuing without server in dev',
    (tester) async {
      final notifier = _FakeConnectNotifier('success');
      await tester.pumpWidget(_host(notifier: notifier, showDevBypass: true));

      final devButton = find.byKey(
        const Key('server-connect-continue-offline'),
      );
      expect(devButton, findsOneWidget);
      expect(find.text('Continue without server (Dev)'), findsOneWidget);

      await tester.ensureVisible(devButton);
      await tester.tap(devButton);
      await tester.pumpAndSettle();

      expect(notifier.continueWithoutServerCalls, 1);
    },
  );

  testWidgets('hides dev bypass button when showDevBypass is false', (
    tester,
  ) async {
    final notifier = _FakeConnectNotifier('success');
    await tester.pumpWidget(_host(notifier: notifier, showDevBypass: false));

    expect(
      find.byKey(const Key('server-connect-continue-offline')),
      findsNothing,
    );
    expect(find.text('Continue without server (Dev)'), findsNothing);
  });

  testWidgets('calls custom onContinueWithoutServer callback if provided', (
    tester,
  ) async {
    final notifier = _FakeConnectNotifier('success');
    var callbackCalled = false;
    await tester.pumpWidget(
      _host(
        notifier: notifier,
        showDevBypass: true,
        onContinueWithoutServer: () => callbackCalled = true,
      ),
    );

    final devButton = find.byKey(const Key('server-connect-continue-offline'));
    await tester.ensureVisible(devButton);
    await tester.tap(devButton);
    await tester.pumpAndSettle();

    expect(callbackCalled, isTrue);
    expect(notifier.continueWithoutServerCalls, 0);
  });
}
