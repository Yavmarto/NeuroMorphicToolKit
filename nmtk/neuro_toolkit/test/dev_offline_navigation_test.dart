import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/server_access_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ConnectNotifier continueWithoutServer sets phase to devOffline', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(connectNotifierProvider).phase, ConnectPhase.idle);

    container.read(connectNotifierProvider.notifier).continueWithoutServer();

    expect(
      container.read(connectNotifierProvider).phase,
      ConnectPhase.devOffline,
    );

    container.read(connectNotifierProvider.notifier).logout();

    expect(container.read(connectNotifierProvider).phase, ConnectPhase.idle);
  });

  test(
    'ModuleNotifier loads bundled modules when in devOffline mode',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(connectNotifierProvider.notifier).continueWithoutServer();

      final moduleState = await container.read(moduleProvider.future);

      expect(moduleState.modules.isNotEmpty, isTrue);
      expect(moduleState.modules.any((m) => m.id == 'neurocnl'), isTrue);
      expect(moduleState.modules.any((m) => m.id == 'Neurobench'), isTrue);
    },
  );

  test(
    'WorkspaceNotifier performs in-memory session operations in dev offline mode',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(connectNotifierProvider.notifier).continueWithoutServer();

      final initialWorkspace = await container.read(workspaceProvider.future);
      expect(initialWorkspace.sessions, isEmpty);

      // ensureDefaultSessionsOnce
      const session1 = WorkspaceSession(
        moduleId: 'neurocnl',
        surfaceMode: 'native',
        readinessState: 'ready',
      );
      await container
          .read(workspaceProvider.notifier)
          .ensureDefaultSessionsOnce(
            sessions: [session1],
            focusedModuleId: 'neurocnl',
          );

      var current = container.read(workspaceProvider).value!;
      expect(current.sessions.length, 1);
      expect(current.focusedModuleId, 'neurocnl');
      expect(current.defaultSessionsEnsured, isTrue);

      // openSession for another module
      await container
          .read(workspaceProvider.notifier)
          .openSession(
            'Neurobench',
            surfaceMode: 'native',
            readinessState: 'ready',
          );

      current = container.read(workspaceProvider).value!;
      expect(current.sessions.length, 2);
      expect(current.focusedModuleId, 'Neurobench');

      // focusSession back to neurocnl
      await container.read(workspaceProvider.notifier).focusSession('neurocnl');
      current = container.read(workspaceProvider).value!;
      expect(current.focusedModuleId, 'neurocnl');

      // updateSession
      await container
          .read(workspaceProvider.notifier)
          .updateSession('neurocnl', readinessState: 'degraded');
      current = container.read(workspaceProvider).value!;
      expect(
        current.sessions
            .firstWhere((s) => s.moduleId == 'neurocnl')
            .readinessState,
        'degraded',
      );

      // closeSession
      await container
          .read(workspaceProvider.notifier)
          .closeSession('Neurobench');
      current = container.read(workspaceProvider).value!;
      expect(current.sessions.length, 1);
      expect(current.sessions.first.moduleId, 'neurocnl');
    },
  );

  testWidgets(
    'ServerConnectScreen dev button transitions ServerAccessGate to child',
    (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ServerAccessGate(
              child: Scaffold(
                body: Center(child: Text('DEV_OFFLINE_WORKSPACE_SHOWN')),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially shows the sign-in popup over the mounted workspace backdrop
      expect(find.text('Sign in to your server'), findsOneWidget);
      expect(find.text('DEV_OFFLINE_WORKSPACE_SHOWN'), findsOneWidget);

      // The dev bypass button should be present in debug mode
      final devBypassButton = find.byKey(
        const Key('server-connect-continue-offline'),
      );
      expect(devBypassButton, findsOneWidget);
      expect(find.text('Continue without server (Dev)'), findsOneWidget);

      // Tap the dev bypass button
      await tester.ensureVisible(devBypassButton);
      await tester.tap(devBypassButton);
      await tester.pumpAndSettle();

      // Now ServerAccessGate should show the workspace child
      expect(find.text('DEV_OFFLINE_WORKSPACE_SHOWN'), findsOneWidget);
      expect(find.text('Sign in to your server'), findsNothing);
    },
  );
}
