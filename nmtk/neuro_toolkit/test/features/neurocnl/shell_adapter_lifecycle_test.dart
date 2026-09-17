import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:neuro_toolkit/features/neurocnl/app.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/shell_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

NmtkFeatureLaunchContext _launchContext({
  required NmtkFeatureErrorReporter onReportError,
  String initialLocation = '/',
}) => NmtkFeatureLaunchContext(
  moduleId: NmtkModuleId.neurocnl,
  backendUri: Uri.parse('http://127.0.0.1:9000/api/neurocnl'),
  onNavigate: (_) async => false,
  onReportError: onReportError,
  onEditServer: () async {},
  initialLocation: initialLocation,
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
  });

  testWidgets('prepares feature persistence before mounting the Studio scope', (
    WidgetTester tester,
  ) async {
    final ready = Completer<void>();
    var initialized = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: NeurocnlShellAdapter(
            launchContext: _launchContext(onReportError: (_) async {}),
            initializeFeature: () async {
              initialized = true;
              await ready.future;
            },
          ),
        ),
      ),
    );

    expect(initialized, isTrue);
    expect(find.byType(NeurocnlStudioSurface), findsNothing);
    ready.complete();
    // Studio owns ongoing visual animations, so a settle would never finish.
    await tester.pump();
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(NeurocnlStudioSurface), findsOneWidget);
    expect(ServerConfigService.instance, isNotNull);
  });

  testWidgets('reports initialization failures to the root host', (
    WidgetTester tester,
  ) async {
    final events = <NmtkFeatureErrorEvent>[];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: NeurocnlShellAdapter(
            launchContext: _launchContext(
              onReportError: (event) async {
                events.add(event);
              },
            ),
            initializeFeature: () async {
              throw StateError('storage unavailable');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('NeuroStudio could not prepare its workspace.'),
      findsOneWidget,
    );
    expect(events, [
      isA<NmtkFeatureErrorEvent>()
          .having((event) => event.moduleId, 'moduleId', NmtkModuleId.neurocnl)
          .having(
            (event) => event.kind,
            'kind',
            NmtkFeatureErrorKind.unexpected,
          ),
    ]);
  });

  testWidgets('reports routed failures to the root host', (
    WidgetTester tester,
  ) async {
    final events = <NmtkFeatureErrorEvent>[];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: NeurocnlShellAdapter(
            launchContext: _launchContext(
              initialLocation: '/missing-route',
              onReportError: (event) async {
                events.add(event);
              },
            ),
            initializeFeature: () async {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.text('Page not found: /missing-route'), findsOneWidget);
    expect(events.single.kind, NmtkFeatureErrorKind.navigation);
  });
}
