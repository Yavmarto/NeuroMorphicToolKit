import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/server/connect/connect_build_policy.dart';
import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/features/server/connect/connect_service.dart';
import 'package:neuro_toolkit/screens/server_access_gate.dart';

/// Drives [connectNotifierProvider] for the gate tests.
class _FakeConnectNotifier extends ConnectNotifier {
  _FakeConnectNotifier(this.behavior, {this.initialState});

  final String behavior; // 'reconnect-ok' | 'reconnect-fail'
  final ConnectState? initialState;
  int reconnectCalls = 0;

  @override
  ConnectState build() => initialState ?? const ConnectState();

  @override
  Future<void> reconnectOnOpen() async {
    if (state.phase == ConnectPhase.connected ||
        state.phase == ConnectPhase.devOffline) {
      return;
    }
    reconnectCalls++;
    state = state.copyWith(phase: ConnectPhase.reconnecting);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (behavior == 'reconnect-ok') {
      state = const ConnectState(
        phase: ConnectPhase.connected,
        session: ConnectSession(
          host: '203.0.113.90',
          username: 'alice',
          sessionToken: 'tok-1',
        ),
        savedHost: '203.0.113.90',
      );
    } else {
      state = const ConnectState(
        phase: ConnectPhase.failed,
        failureCause: 'Incorrect username or password.',
        savedHost: '203.0.113.90',
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
        sessionToken: 'tok-1',
      ),
      savedHost: request.host,
      savedUsername: request.appUsername,
    );
  }
}

Widget _harness(_FakeConnectNotifier notifier) {
  return ProviderScope(
    overrides: [connectNotifierProvider.overrideWith(() => notifier)],
    child: const MaterialApp(
      home: ServerAccessGate(
        child: Scaffold(body: Center(child: Text('WORKSPACE'))),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the workspace immediately when reconnect succeeds', (
    tester,
  ) async {
    final notifier = _FakeConnectNotifier('reconnect-ok');
    await tester.pumpWidget(_harness(notifier));

    // While reconnect is in flight, the gate shows a reconnecting view and
    // hides the workspace so empty-module UI cannot flash underneath.
    await tester.pump();
    expect(find.text('Reconnecting to your server…'), findsOneWidget);
    expect(find.text('WORKSPACE'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('WORKSPACE'), findsOneWidget);
    expect(notifier.reconnectCalls, 1);
  });

  testWidgets(
    'shows the connect form when reconnect fails or no saved server',
    (tester) async {
      final notifier = _FakeConnectNotifier('reconnect-fail');
      await tester.pumpWidget(_harness(notifier));

      await tester.pumpAndSettle();

      expect(
        find.text(
          ConnectBuildPolicy.requiresCredentialAuth
              ? 'Sign in to your server'
              : 'Connect to your server',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          Key(
            ConnectBuildPolicy.requiresCredentialAuth
                ? 'server-connect-sign-in'
                : 'server-connect-connect',
          ),
        ),
        findsOneWidget,
      );
      // The failed reconnect's reason is surfaced on the form.
      expect(
        find.textContaining('Incorrect username or password'),
        findsWidgets,
      );
      // The workspace stays mounted behind the popup (CEL-103).
      expect(find.text('WORKSPACE'), findsOneWidget);
    },
  );

  testWidgets(
    'offers a path to set up a brand-new server from the connect form',
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
    },
  );

  testWidgets('back affordance on setup returns to the connect form', (
    tester,
  ) async {
    final notifier = _FakeConnectNotifier('reconnect-fail');
    await tester.pumpWidget(_harness(notifier));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('server-connect-new-server')),
    );
    await tester.tap(find.byKey(const Key('server-connect-new-server')));
    await tester.pumpAndSettle();

    expect(find.text('Set up your server'), findsOneWidget);

    await tester.tap(find.byKey(const Key('server-setup-back')));
    await tester.pumpAndSettle();

    // Back on the connect form, not stuck in the setup dead end (CEL-88).
    expect(find.text('Set up your server'), findsNothing);
    expect(
      find.text(
        ConnectBuildPolicy.requiresCredentialAuth
            ? 'Sign in to your server'
            : 'Connect to your server',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        Key(
          ConnectBuildPolicy.requiresCredentialAuth
              ? 'server-connect-sign-in'
              : 'server-connect-connect',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'connecting does not touch ref after the gate unmounts the form',
    (tester) async {
      final notifier = _FakeConnectNotifier('reconnect-fail');
      await tester.pumpWidget(_harness(notifier));
      await tester.pumpAndSettle();

      if (ConnectBuildPolicy.requiresCredentialAuth) {
        await tester.enterText(
          find.byKey(const Key('server-connect-username')),
          'alice',
        );
        await tester.enterText(
          find.byKey(const Key('server-connect-password')),
          'secret',
        );
      }
      final connectButton = find.byKey(
        Key(
          ConnectBuildPolicy.requiresCredentialAuth
              ? 'server-connect-sign-in'
              : 'server-connect-connect',
        ),
      );
      await tester.ensureVisible(connectButton);
      await tester.tap(connectButton);
      // The gate flips to `connected` and unmounts ServerConnectScreen while
      // its `connect()` await is still pending -- flutter_test rethrows any
      // exception from that dangling future, so this settling without error
      // is the regression check.
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('WORKSPACE'), findsOneWidget);
    },
  );

  testWidgets('shows the workspace when in devOffline phase', (tester) async {
    final notifier = _FakeConnectNotifier(
      'reconnect-fail',
      initialState: const ConnectState(phase: ConnectPhase.devOffline),
    );
    await tester.pumpWidget(_harness(notifier));
    await tester.pumpAndSettle();

    expect(find.text('WORKSPACE'), findsOneWidget);
  });
}
