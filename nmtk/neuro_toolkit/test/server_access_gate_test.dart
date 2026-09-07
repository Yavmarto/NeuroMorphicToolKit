import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/features/server/connect/connect_service.dart';
import 'package:neuro_toolkit/screens/server_access_gate.dart';

/// Drives [connectNotifierProvider] for the gate tests.
class _FakeConnectNotifier extends ConnectNotifier {
  _FakeConnectNotifier(this.behavior);

  final String behavior; // 'reconnect-ok' | 'reconnect-fail'
  int reconnectCalls = 0;

  @override
  ConnectState build() => const ConnectState();

  @override
  Future<void> reconnectOnOpen() async {
    reconnectCalls++;
    state = state.copyWith(phase: ConnectPhase.reconnecting);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (behavior == 'reconnect-ok') {
      state = ConnectState(
        phase: ConnectPhase.connected,
        session: const ConnectSession(
          host: '192.168.2.90',
          username: 'alice',
          sessionToken: 'token',
        ),
        savedHost: '192.168.2.90',
      );
    } else {
      state = ConnectState(
        phase: ConnectPhase.failed,
        failureCause: 'Incorrect username or password.',
        savedHost: '192.168.2.90',
      );
    }
  }

  @override
  Future<void> connect(ConnectRequest request) async {
    state = state.copyWith(phase: ConnectPhase.reconnecting);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // ServerAccessGate swaps ServerConnectScreen out for the workspace the
    // instant this flips to connected, unmounting the form mid-`connect()`
    // call -- the regression this state transition is designed to trigger.
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

Widget _harness(_FakeConnectNotifier notifier) {
  return ProviderScope(
    overrides: [
      connectNotifierProvider.overrideWith(() => notifier),
    ],
    child: MaterialApp(
      home: ServerAccessGate(
        child: const Scaffold(body: Center(child: Text('WORKSPACE'))),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the workspace immediately when reconnect succeeds',
      (tester) async {
    final notifier = _FakeConnectNotifier('reconnect-ok');
    await tester.pumpWidget(_harness(notifier));

    // While reconnect is in flight, the gate shows a reconnecting view.
    await tester.pump();
    expect(find.text('Reconnecting to your server…'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('WORKSPACE'), findsOneWidget);
    expect(notifier.reconnectCalls, 1);
  });

  testWidgets('shows the connect form when reconnect fails or no saved server',
      (tester) async {
    final notifier = _FakeConnectNotifier('reconnect-fail');
    await tester.pumpWidget(_harness(notifier));

    await tester.pumpAndSettle();

    expect(find.text('Sign in to your server'), findsOneWidget);
    expect(find.byKey(const Key('server-connect-sign-in')), findsOneWidget);
    // The failed reconnect's reason is surfaced on the form.
    expect(find.textContaining('Incorrect username or password'), findsWidgets);
    // No workspace yet.
    expect(find.text('WORKSPACE'), findsNothing);
  });

  testWidgets('offers a path to set up a brand-new server from the connect form',
      (tester) async {
    final notifier = _FakeConnectNotifier('reconnect-fail');
    await tester.pumpWidget(_harness(notifier));

    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('server-connect-new-server')),
    );
    await tester.tap(find.byKey(const Key('server-connect-new-server')));
    await tester.pumpAndSettle();

    expect(find.text('Set up your server'), findsOneWidget);
    expect(find.byKey(const Key('server-setup-provision')), findsOneWidget);
  });

  testWidgets(
      'signing in does not touch ref after the gate unmounts the form',
      (tester) async {
    final notifier = _FakeConnectNotifier('reconnect-fail');
    await tester.pumpWidget(_harness(notifier));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '192.168.2.90');
    await tester.enterText(find.byType(TextField).at(1), 'alice');
    await tester.enterText(find.byType(TextField).at(2), 'secret');

    await tester.ensureVisible(
      find.byKey(const Key('server-connect-sign-in')),
    );
    await tester.tap(find.byKey(const Key('server-connect-sign-in')));
    // The gate flips to `connected` and unmounts ServerConnectScreen while
    // its `connect()` await is still pending -- flutter_test rethrows any
    // exception from that dangling future, so this settling without error
    // is the regression check.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('WORKSPACE'), findsOneWidget);
  });
}
