import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:neuro_toolkit/screens/tool_view/cross_module_navigation.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

const _connectionEvent = NmtkFeatureErrorEvent(
  moduleId: NmtkModuleId.neurocnl,
  kind: NmtkFeatureErrorKind.connection,
  message: 'NeuroStudio cannot reach the selected backend.',
);

const _authenticationEvent = NmtkFeatureErrorEvent(
  moduleId: NmtkModuleId.neurocnl,
  kind: NmtkFeatureErrorKind.authentication,
  message: 'NeuroStudio cannot authenticate with the selected backend.',
);

const _navigationEvent = NmtkFeatureErrorEvent(
  moduleId: NmtkModuleId.neurocnl,
  kind: NmtkFeatureErrorKind.navigation,
  message: 'NeuroStudio could not open the requested page.',
);

/// Mounts an [NmtkNotificationCenter] (as the app's `MaterialApp.builder`
/// does) and returns a [BuildContext] inside its scope.
Future<BuildContext> _pumpWithNotificationHost(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: const NmtkNotificationCenter(
        child: Scaffold(body: Center(child: Text('workspace'))),
      ),
    ),
  );
  return tester.element(find.text('workspace'));
}

void main() {
  testWidgets(
    'connection errors show a top-right banner instead of a SnackBar',
    (tester) async {
      final context = await _pumpWithNotificationHost(tester);
      var openedBackendSetup = 0;

      await reportHostedFeatureError(
        context,
        _connectionEvent,
        onOpenBackendSetup: () => openedBackendSetup++,
      );
      // Connection reports are grace-suppressed at startup so a still-starting
      // backend does not flash a permanent-looking banner; it promotes only
      // once the grace window expires with the backend still failing.
      await tester.pump(hostedFeatureErrorStartupGrace);
      await tester.pumpAndSettle();

      expect(find.text('Connection Problem'), findsOneWidget);
      expect(find.text(_connectionEvent.message), findsOneWidget);
      expect(find.text('Backend Setup'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      // The "Backend Setup" action still fires and dismisses the banner.
      await tester.tap(find.text('Backend Setup'));
      await tester.pumpAndSettle();

      expect(openedBackendSetup, 1);
      expect(find.text('Connection Problem'), findsNothing);
    },
  );

  testWidgets('repeat connection reports coalesce into one banner', (
    tester,
  ) async {
    final context = await _pumpWithNotificationHost(tester);

    await reportHostedFeatureError(
      context,
      _connectionEvent,
      onOpenBackendSetup: () {},
    );
    await reportHostedFeatureError(
      context,
      _connectionEvent,
      onOpenBackendSetup: () {},
    );
    await tester.pump(hostedFeatureErrorStartupGrace);
    await tester.pumpAndSettle();

    expect(find.text('Connection Problem'), findsOneWidget);
    expect(find.byIcon(ZetaIcons.cloud_off), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('authentication errors use the same banner with their title', (
    tester,
  ) async {
    final context = await _pumpWithNotificationHost(tester);

    await reportHostedFeatureError(
      context,
      _authenticationEvent,
      onOpenBackendSetup: () {},
    );
    await tester.pump(hostedFeatureErrorStartupGrace);
    await tester.pumpAndSettle();

    expect(find.text('Authentication Problem'), findsOneWidget);
    expect(find.text(_authenticationEvent.message), findsOneWidget);
    expect(find.text('Backend Setup'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a recovery during the grace window never shows the banner', (
    tester,
  ) async {
    final context = await _pumpWithNotificationHost(tester);

    // Startup race (CEL-129): a couple of failed requests while the backend is
    // still warming up, then a successful request before the grace window ends.
    await reportHostedFeatureError(
      context,
      _connectionEvent,
      onOpenBackendSetup: () {},
    );
    await reportHostedFeatureError(
      context,
      _connectionEvent,
      onOpenBackendSetup: () {},
    );
    await clearHostedFeatureError(context);
    await tester.pump(hostedFeatureErrorStartupGrace);
    await tester.pumpAndSettle();

    expect(find.text('Connection Problem'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'a recovery after the banner is live dismisses the stale banner',
    (tester) async {
      final context = await _pumpWithNotificationHost(tester);

      // Backend died mid-session: the banner promotes after the grace window…
      await reportHostedFeatureError(
        context,
        _connectionEvent,
        onOpenBackendSetup: () {},
      );
      await tester.pump(hostedFeatureErrorStartupGrace);
      await tester.pumpAndSettle();
      expect(find.text('Connection Problem'), findsOneWidget);

      // …then a later request succeeds and the banner must go away (CEL-129).
      await clearHostedFeatureError(context);
      await tester.pumpAndSettle();
      expect(find.text('Connection Problem'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'a recovery after the banner is live also dismisses an auth banner',
    (tester) async {
      final context = await _pumpWithNotificationHost(tester);

      await reportHostedFeatureError(
        context,
        _authenticationEvent,
        onOpenBackendSetup: () {},
      );
      await tester.pump(hostedFeatureErrorStartupGrace);
      await tester.pumpAndSettle();
      expect(find.text('Authentication Problem'), findsOneWidget);

      await clearHostedFeatureError(context);
      await tester.pumpAndSettle();
      expect(find.text('Authentication Problem'), findsNothing);
    },
  );

  testWidgets('navigation errors show a top-right banner', (
    tester,
  ) async {
    final context = await _pumpWithNotificationHost(tester);

    await reportHostedFeatureError(
      context,
      _navigationEvent,
      onOpenBackendSetup: () {},
    );
    await tester.pumpAndSettle();

    expect(find.text('NeuroStudio Problem'), findsOneWidget);
    expect(find.text(_navigationEvent.message), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Backend Setup'), findsNothing);

    await tester.tap(find.byIcon(ZetaIcons.close_sharp));
    await tester.pumpAndSettle();
    expect(find.text('NeuroStudio Problem'), findsNothing);
  });

  testWidgets(
    'without a mounted host, connection errors are suppressed',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(body: Center(child: Text('bare workspace'))),
        ),
      );
      final context = tester.element(find.text('bare workspace'));

      await reportHostedFeatureError(
        context,
        _connectionEvent,
        onOpenBackendSetup: () {},
      );
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Connection Problem'), findsNothing);
    },
  );
}
