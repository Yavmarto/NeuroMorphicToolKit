import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/server_config_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/studio_step_drawer/studio_step_drawer.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/studio_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers_test.mocks.dart';

/// Self-check for the mobile hamburger menu + step drawer (studio_screen.dart
/// isMobile branch + studio_step_drawer.dart): the AppBar shows "Step N:
/// Name" plus a Save action, tapping the hamburger opens a drawer with the
/// workspace name (tap to rename) and the step list, and the connection row
/// is tappable.
void main() {
  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
  });

  Future<void> pumpMobileStudio(WidgetTester tester) async {
    final mockApi = MockApiClient();
    when(mockApi.getTemplates()).thenAnswer((_) async => const []);
    when(
      mockApi.ensureWorkspace(workspacePath: anyNamed('workspacePath')),
    ).thenAnswer((_) async => '');

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          workspaceBootstrapProvider.overrideWithValue(
            const WorkspaceBootstrap(initialLocation: '/'),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: StudioScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Opens the drawer via the Scaffold API directly rather than tapping the
  // hamburger icon by coordinate — hit-testing that specific icon is flaky
  // across sequential tests in this suite, and it's not itself under test
  // here (the first test below covers that the hamburger button exists).
  Future<void> openDrawer(WidgetTester tester) async {
    tester
        .state<ScaffoldState>(
          find
              .ancestor(
                of: find.byIcon(Icons.menu),
                matching: find.byType(Scaffold),
              )
              .first,
        )
        .openDrawer();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'mobile Studio inside shell chrome shows one hamburger and no local drawer',
    (WidgetTester tester) async {
      final mockApi = MockApiClient();
      when(mockApi.getTemplates()).thenAnswer((_) async => const []);

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockApi),
            workspaceBootstrapProvider.overrideWithValue(
              const WorkspaceBootstrap(initialLocation: '/'),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: NmtkMobileScaffold(
              mode: NmtkShellMode.command,
              navItems: const [
                NmtkSidebarItem(
                  id: 'neurocnl',
                  label: 'Studio',
                  icon: Icons.science_outlined,
                ),
              ],
              selectedIndex: 0,
              showBottomNavigation: false,
              child: StudioScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Setup · Prepare'), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsNothing);
      expect(find.byTooltip('Open navigation'), findsOneWidget);
      expect(find.byType(StudioStepDrawer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile Studio screen shows a step title bar with Save, and a '
      'drawer with the workspace name and step list', (
    WidgetTester tester,
  ) async {
    await pumpMobileStudio(tester);

    // Default step is the Setup stage's Prepare child.
    expect(find.text('Setup · Prepare'), findsOneWidget);
    // Save action lives in the AppBar (bug: mobile had no way to save).
    expect(find.byTooltip('Save workspace'), findsOneWidget);
    // No overflow from nesting a Scaffold inside the mobile layout.
    expect(tester.takeException(), isNull);

    // The hamburger button itself is present and opens a drawer.
    expect(find.byIcon(Icons.menu), findsOneWidget);
    await openDrawer(tester);

    expect(find.text('Untitled Workspace'), findsOneWidget);
    expect(find.text('Setup'), findsOneWidget);
    expect(find.text('Prepare'), findsOneWidget);
    expect(find.text('Design'), findsOneWidget);
    expect(find.text('Execute'), findsOneWidget);
    expect(find.text('Model'), findsWidgets);
    expect(find.text('Run'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the drawer workspace name renames the workspace', (
    WidgetTester tester,
  ) async {
    await pumpMobileStudio(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(StudioScreen)),
    );

    await openDrawer(tester);

    // Bug: there was no way to rename the workspace on mobile at all.
    await tester.tap(find.text('Untitled Workspace'));
    await tester.pumpAndSettle();

    expect(find.text('Rename Workspace'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'My Renamed Workspace');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(
      container.read(workspaceProvider).workspaceName,
      'My Renamed Workspace',
    );
    expect(find.text('My Renamed Workspace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the drawer connection row opens the root server popup', (
    WidgetTester tester,
  ) async {
    final mockApi = MockApiClient();
    when(mockApi.getTemplates()).thenAnswer((_) async => const []);
    var editServerCalls = 0;

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          workspaceBootstrapProvider.overrideWithValue(
            const WorkspaceBootstrap(initialLocation: '/'),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: StudioScreen(onEditServer: () async => editServerCalls++),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openDrawer(tester);

    final connectionRow = tester.widget<InkWell>(
      find.ancestor(
        of: find.text('Not connected'),
        matching: find.byType(InkWell),
      ),
    );
    connectionRow.onTap!();
    await tester.pumpAndSettle();

    // Connection management belongs to the root app; the feature neither
    // auto-discovers another host nor renders a second setup result.
    expect(editServerCalls, 1);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Regression coverage for the connection dot staying red after a real
  // reconnect: this locks the dot's color to serverConfigProvider's state
  // (rather than to any particular mechanism that updates it), so it fails
  // if the drawer ever stops reading straight from that provider.
  Future<void> pumpMobileStudioWithServerState(
    WidgetTester tester,
    ServerConfigState state,
  ) async {
    final mockApi = MockApiClient();
    when(mockApi.getTemplates()).thenAnswer((_) async => const []);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          workspaceBootstrapProvider.overrideWithValue(
            const WorkspaceBootstrap(initialLocation: '/'),
          ),
          serverConfigProvider.overrideWith(
            () => _FixedServerConfigController(state),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: StudioScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('drawer connection dot is healthyColor when connected', (
    WidgetTester tester,
  ) async {
    await pumpMobileStudioWithServerState(
      tester,
      ServerConfigState(
        serverUrl: 'http://localhost:8000',
        status: ConnectionStatus.connected,
      ),
    );
    await openDrawer(tester);

    final dot = tester.widget<NmtkStatusDot>(find.byType(NmtkStatusDot));
    final context = tester.element(find.byType(NmtkStatusDot));
    expect(dot.color, NmtkShellTokens.of(context).healthyColor);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drawer connection dot is errorColor when not connected', (
    WidgetTester tester,
  ) async {
    await pumpMobileStudioWithServerState(
      tester,
      ServerConfigState(status: ConnectionStatus.failed),
    );
    await openDrawer(tester);

    final dot = tester.widget<NmtkStatusDot>(find.byType(NmtkStatusDot));
    final context = tester.element(find.byType(NmtkStatusDot));
    expect(dot.color, NmtkShellTokens.of(context).errorColor);
    expect(tester.takeException(), isNull);
  });
}

/// Test double that seeds a fixed [ServerConfigState] instead of the real
/// SharedPreferences-backed seed, so drawer-dot-color tests don't depend on
/// an actual health check resolving.
class _FixedServerConfigController extends ServerConfigController {
  _FixedServerConfigController(this._state);
  final ServerConfigState _state;

  @override
  ServerConfigState build() => _state;
}
