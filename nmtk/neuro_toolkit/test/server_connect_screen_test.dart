import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/features/server/connect/connect_service.dart';
import 'package:neuro_toolkit/screens/server_connect_screen.dart';

/// Functional stand-in that drives [connectNotifierProvider] through the exact
/// state transitions the real notifier produces.
class _FakeConnectNotifier extends ConnectNotifier {
  _FakeConnectNotifier(this.behavior, {ConnectState? initialState})
    : _initial = initialState;

  final String behavior; // 'success' | 'failure'
  final ConnectState? _initial;

  int connectCalls = 0;
  ConnectRequest? lastRequest;

  @override
  ConnectState build() => _initial ?? const ConnectState();

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

Widget _host({required _FakeConnectNotifier notifier}) {
  return ProviderScope(
    overrides: [
      connectNotifierProvider.overrideWith(() => notifier),
    ],
    child: const MaterialApp(home: ServerConnectScreen()),
  );
}

void main() {
  testWidgets('connect form collects host, app username and password',
      (tester) async {
    final notifier = _FakeConnectNotifier('success');
    await tester.pumpWidget(_host(notifier: notifier));

    expect(find.text('Sign in to your server'), findsOneWidget);
    expect(find.text('Server address'), findsWidgets);
    expect(find.text('App username'), findsOneWidget);
    expect(find.text('Password'), findsWidgets);

    await tester.enterText(
      find.widgetWithText(NmtkTextInput, 'Server address'),
      '192.168.2.90',
    );
    await tester.enterText(
      find.widgetWithText(NmtkTextInput, 'App username'),
      'alice',
    );
    await tester.enterText(
      find.widgetWithText(NmtkTextInput, 'Password'),
      'secret',
    );
    await tester.ensureVisible(find.byKey(const Key('server-connect-sign-in')));
    await tester.tap(find.byKey(const Key('server-connect-sign-in')));
    await tester.pumpAndSettle();

    expect(notifier.connectCalls, 1);
    expect(notifier.lastRequest?.host, '192.168.2.90');
    expect(notifier.lastRequest?.appUsername, 'alice');
    expect(notifier.lastRequest?.credential, 'secret');
  });

  testWidgets('pre-fills the saved host from the connect state', (tester) async {
    final notifier = _FakeConnectNotifier(
      'success',
      initialState: const ConnectState(
        phase: ConnectPhase.failed,
        savedHost: '192.168.2.90',
        failureCause: 'Incorrect username or password.',
      ),
    );
    await tester.pumpWidget(_host(notifier: notifier));

    final hostField = tester.widget<NmtkTextInput>(
      find.widgetWithText(NmtkTextInput, 'Server address'),
    );
    expect(hostField.controller?.text, '192.168.2.90');
  });

  testWidgets('shows plain-English failure and a retry that re-invokes',
      (tester) async {
    final notifier = _FakeConnectNotifier('failure');
    await tester.pumpWidget(_host(notifier: notifier));

    await tester.enterText(
      find.widgetWithText(NmtkTextInput, 'Server address'),
      '192.168.2.90',
    );
    await tester.enterText(
      find.widgetWithText(NmtkTextInput, 'App username'),
      'alice',
    );
    await tester.enterText(
      find.widgetWithText(NmtkTextInput, 'Password'),
      'wrong',
    );
    await tester.ensureVisible(find.byKey(const Key('server-connect-sign-in')));
    await tester.tap(find.byKey(const Key('server-connect-sign-in')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('server-connect-error')), findsOneWidget);
    expect(find.textContaining('Incorrect username or password'), findsWidgets);
    for (final word in const ['SSH', 'sudo', 'docker', 'stderr', 'exit code']) {
      expect(find.textContaining(word), findsNothing);
    }

    // The form is still present, so the user can correct and sign in again.
    await tester.ensureVisible(find.byKey(const Key('server-connect-sign-in')));
    await tester.tap(find.byKey(const Key('server-connect-sign-in')));
    await tester.pumpAndSettle();
    expect(notifier.connectCalls, 2);
  });

  testWidgets('shows a reconnecting panel while the connect call is in flight',
      (tester) async {
    final notifier = _FakeConnectNotifier('success');
    await tester.pumpWidget(_host(notifier: notifier));

    await tester.enterText(
      find.widgetWithText(NmtkTextInput, 'Server address'),
      '192.168.2.90',
    );
    await tester.enterText(
      find.widgetWithText(NmtkTextInput, 'App username'),
      'alice',
    );
    await tester.enterText(
      find.widgetWithText(NmtkTextInput, 'Password'),
      'secret',
    );
    await tester.ensureVisible(find.byKey(const Key('server-connect-sign-in')));
    await tester.tap(find.byKey(const Key('server-connect-sign-in')));
    await tester.pump();

    expect(
      find.byKey(const Key('server-connect-reconnecting')),
      findsOneWidget,
    );
    expect(find.text('Reconnecting to your server…'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('form validation rejects a blank address without calling the API',
      (tester) async {
    final notifier = _FakeConnectNotifier('success');
    await tester.pumpWidget(_host(notifier: notifier));

    await tester.ensureVisible(find.byKey(const Key('server-connect-sign-in')));
    await tester.tap(find.byKey(const Key('server-connect-sign-in')));
    await tester.pumpAndSettle();

    expect(notifier.connectCalls, 0);
    expect(
      find.textContaining('Enter the server address'),
      findsWidgets,
    );
  });
}
