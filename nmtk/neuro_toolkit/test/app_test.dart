import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/neurocnl_studio.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/workspace/native_surface_registry.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _noopEditServer() async {}
Future<void> _noopReportError(NmtkFeatureErrorEvent event) async {}

void main() {
  testWidgets('root app is the only MaterialApp around NeuroStudio', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final launchContext = NmtkFeatureLaunchContext(
      moduleId: NmtkModuleId.neurocnl,
      backendUri: Uri.parse('http://127.0.0.1:9000/api/neurocnl'),
      initialLocation: '/single-app-boundary-test',
      onNavigate: (_) async => false,
      onReportError: _noopReportError,
      onEditServer: _noopEditServer,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: NmtkZetaTheme.wrap(
          builder: (context, light, dark, mode) => MaterialApp(
            theme: light,
            darkTheme: dark,
            themeMode: mode,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: NativeSurfaceRegistry.build(
              const WorkspaceSession(
                moduleId: 'neurocnl',
                surfaceMode: 'native',
                readinessState: 'ready',
                deepLink: '/single-app-boundary-test',
              ),
              launchContext: launchContext,
            ),
          ),
        ),
      ),
    );
    // The embedded Studio surface has continuous visual animations, so a
    // settle never completes. Advance its adapter initialization instead.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    final surfaceContext = tester.element(find.byType(NeurocnlShellAdapter));
    final adapter = tester.widget<NeurocnlShellAdapter>(
      find.byType(NeurocnlShellAdapter),
    );
    expect(adapter.launchContext, same(launchContext));
    expect(AppLocalizations.of(surfaceContext), isNotNull);
    expect(Theme.of(surfaceContext).brightness, Brightness.dark);
  });
}
