// Basic widget test for neurocnl Studio.
//
// These tests verify that core widgets can be instantiated and rendered.
// They use a ProviderScope wrapper since the app uses Riverpod for state.
//
// Run: flutter test

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:go_router/go_router.dart';
import 'package:neuro_toolkit/features/neurocnl/app.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/shell_adapter.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/cnl_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'utils/fake_webview.dart';
import 'support/neurocnl_surface_test_host.dart';

void main() {
  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    WebViewPlatform.instance = FakeWebViewPlatform();
    ServerConfigService.debugResetForTests();
    SharedPreferences.setMockInitialValues({
      'neurocnl_server_url': 'http://localhost:8000',
    });
    await ServerConfigService.initialize();
  });

  Future<void> pumpAppAt(WidgetTester tester, String initialLocation) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildNeurocnlSurfaceTestHost(initialLocation: initialLocation),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await pumpAppAt(tester, '/');
  }

  Future<void> pumpAppToModel(WidgetTester tester) async {
    await pumpApp(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NeurocnlStudioSurface)),
    );
    container
        .read(workspaceProvider.notifier)
        .setActivePipelineStep('defineModel');
    await tester.pumpAndSettle();
  }

  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await pumpAppToModel(tester);

    await tester.tap(find.byTooltip('CNL Editor'));
    await tester.pumpAndSettle();

    expect(find.text('Untitled Workspace'), findsWidgets);
    expect(find.byTooltip('Show templates'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Templates button is present', (WidgetTester tester) async {
    await pumpAppToModel(tester);

    await tester.tap(find.byTooltip('CNL Editor'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Show templates'), findsOneWidget);
  });

  testWidgets('template action opens gallery dialog without layout errors', (
    WidgetTester tester,
  ) async {
    await pumpAppToModel(tester);

    await tester.tap(find.byTooltip('CNL Editor'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show templates'));
    await tester.pumpAndSettle();

    expect(find.text('Template Gallery'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Play button is absent (auto-run mode)', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    // Play button removed — parse/validate runs automatically on edit.
    expect(find.byKey(const Key('play-stop-button')), findsNothing);
    expect(find.byKey(const Key('play-icon')), findsNothing);
  });

  testWidgets('Workspace action buttons are present', (
    WidgetTester tester,
  ) async {
    await pumpAppToModel(tester);

    await tester.tap(find.byTooltip('CNL Editor'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Show templates'), findsOneWidget);
    expect(find.byTooltip('Save workspace'), findsOneWidget);
  });

  testWidgets('Pipeline bar shows stages and only the active stage child', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Setup'), findsOneWidget);
    expect(find.text('Design'), findsOneWidget);
    expect(find.text('Execute'), findsOneWidget);
    expect(find.text('Prepare').hitTestable(), findsOneWidget);
    expect(find.text('Model').hitTestable(), findsNothing);
    expect(find.text('Run').hitTestable(), findsNothing);
    expect(find.text('Preview'), findsNothing);
    expect(find.text('Parse'), findsNothing);
  });

  testWidgets('Studio deploy panel is the canonical deployment path', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: NmtkZetaTheme.wrap(
          builder: (context, light, dark, mode) => MaterialApp(
            theme: light,
            darkTheme: dark,
            themeMode: mode,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: NeurocnlShellAdapter(
              launchContext: NmtkFeatureLaunchContext(
                moduleId: NmtkModuleId.neurocnl,
                backendUri: Uri.parse(kTestNeurocnlServerUrl),
                initialLocation: '/?panel=deploy',
                onNavigate: (_) async => false,
                onReportError: (_) async {},
                onEditServer: noopEditServer,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Deploy deep links open the dedicated seventh step directly.
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const Key('deploy-targets-overview')), findsOneWidget);
  });

  testWidgets('App rebuilds preserve the active embedded route', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: _HostRebuildHarness(
          child: NeurocnlStudioSurface(onEditServer: noopEditServer),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(NeurocnlStudioSurface)),
    );
    container
        .read(workspaceProvider.notifier)
        .setActivePipelineStep('defineModel');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('CNL Editor'));
    await tester.pumpAndSettle();

    final studioContext = tester.element(
      find.byTooltip('Show templates').first,
    );
    GoRouter.of(studioContext).go('/analysis');
    await tester.pumpAndSettle();

    // '/analysis' resolves directly to the dedicated Deploy step.
    expect(find.byKey(const Key('deploy-targets-overview')), findsOneWidget);

    await tester.tap(find.byKey(_HostRebuildHarness.rebuildButtonKey));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('deploy-targets-overview')), findsOneWidget);
  });

  testWidgets('Canvas export route renders inside the shared shell', (
    WidgetTester tester,
  ) async {
    await pumpAppAt(tester, '/canvas/export');

    expect(find.text('Export Design'), findsWidgets);
    expect(find.text('Export'), findsWidgets);
  });

  testWidgets('Canvas base route restores the visual canvas shell', (
    WidgetTester tester,
  ) async {
    await pumpAppAt(tester, '/canvas');

    expect(find.byType(CnlEditor), findsNothing);
    expect(find.byType(NetworkCanvas), findsOneWidget);
  });

  testWidgets('Canvas projects route restores the project workspace', (
    WidgetTester tester,
  ) async {
    await pumpAppAt(tester, '/canvas/projects');

    expect(find.text('Saved Projects'), findsWidgets);
    expect(find.text('Save Current Design'), findsOneWidget);
  });

  testWidgets('Canvas sweep route restores the sweep workspace', (
    WidgetTester tester,
  ) async {
    await pumpAppAt(tester, '/canvas/sweep');

    expect(find.text('Sweep Configuration'), findsOneWidget);
    expect(find.byKey(const Key('sweep-run-button')), findsOneWidget);
  });
}

class _HostRebuildHarness extends StatefulWidget {
  const _HostRebuildHarness({required this.child});

  static const rebuildButtonKey = ValueKey<String>('rebuild-host');

  final Widget child;

  @override
  State<_HostRebuildHarness> createState() => _HostRebuildHarnessState();
}

class _HostRebuildHarnessState extends State<_HostRebuildHarness> {
  var _revision = 0;

  @override
  Widget build(BuildContext context) {
    return NmtkZetaTheme.wrap(
      builder: (context, light, dark, mode) => MaterialApp(
        theme: light,
        darkTheme: dark,
        themeMode: mode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              TextButton(
                key: _HostRebuildHarness.rebuildButtonKey,
                onPressed: () {
                  setState(() {
                    _revision += 1;
                  });
                },
                child: Text('Rebuild host $_revision'),
              ),
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}
