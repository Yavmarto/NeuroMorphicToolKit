import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:neuro_toolkit/screens/settings.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAnalyticsService extends Mock implements AnalyticsService {}

class MockControlApiService extends Mock implements ControlApiService {}

void main() {
  Widget buildApp(SettingsProvider settings) {
    return ProviderScope(
      overrides: [
        settingsStateProvider.overrideWith((ref) => settings),
        analyticsServiceProvider.overrideWithValue(MockAnalyticsService()),
        controlApiServiceProvider.overrideWithValue(MockControlApiService()),
      ],
      child: NmtkZetaTheme.wrap(
        builder: (context, light, dark, mode) => MaterialApp(
          theme: light,
          darkTheme: dark,
          themeMode: mode,
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
  }

  testWidgets('renders Settings heading and General, Logging sections',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();

    await tester.pumpWidget(buildApp(settings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Logging'), findsOneWidget);
  });

  testWidgets('no DropdownButton remains', (tester) async {
    tester.view.physicalSize = const Size(1280, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();

    await tester.pumpWidget(buildApp(settings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(DropdownButton<ThemeMode>), findsNothing);
    expect(find.byType(DropdownButton<LogLevel>), findsNothing);
  });

  testWidgets('General section has Theme and Server rows', (tester) async {
    tester.view.physicalSize = const Size(1280, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();

    await tester.pumpWidget(buildApp(settings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Setup & environments'), findsOneWidget);
  });

  testWidgets('Logging section has Log Level and log actions', (tester) async {
    tester.view.physicalSize = const Size(1280, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();

    await tester.pumpWidget(buildApp(settings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Log Level'), findsOneWidget);
    expect(find.text('Local Crash Logs'), findsOneWidget);
    expect(find.text('Clear Local Logs'), findsOneWidget);
    expect(find.text('Server Logs'), findsOneWidget);
  });
}
