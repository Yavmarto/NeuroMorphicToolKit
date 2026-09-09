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
    await tester.pumpAndSettle();

    expect(find.text('Authentication Problem'), findsOneWidget);
    expect(find.text(_authenticationEvent.message), findsOneWidget);
    expect(find.text('Backend Setup'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('navigation errors keep the bottom SnackBar path', (
    tester,
  ) async {
    final context = await _pumpWithNotificationHost(tester);

    await reportHostedFeatureError(
      context,
      _navigationEvent,
      onOpenBackendSetup: () {},
    );
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(_navigationEvent.message), findsOneWidget);
    expect(find.text('Connection Problem'), findsNothing);
    expect(find.text('Backend Setup'), findsNothing);

    // Close the SnackBar so no dismiss timer is left pending at teardown.
    await tester.tap(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets(
    'without a mounted host, connection errors fall back to SnackBar',
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

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Backend Setup'), findsOneWidget);
      expect(find.text('Connection Problem'), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pumpAndSettle();
    },
  );
}
