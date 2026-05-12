import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:neuro_toolkit/providers/app_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/onboarding.dart';
import 'package:neuro_toolkit/services/preferences_service.dart';
import 'package:nmtk_ui_core/app_theme.dart';
import 'package:nmtk_ui_core/shad_theme.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('onboarding_test');
    PreferencesService().clear();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    PreferencesService().clear();
  });

  testWidgets('selecting a workflow waits for explicit continue',
      (WidgetTester tester) async {
    final prefs = PreferencesService(basePath: tempDir.path);
    await prefs.init();
    final appProvider = AppProvider(preferencesService: prefs);
    await _pumpOnboarding(tester, appProvider);

    await tester.tap(find.byKey(const Key('workflow-researcher')));
    await tester.pump();

    expect(appProvider.hasSeenOnboarding, isFalse);
    expect(find.text('Workspace ready'), findsNothing);
    expect(
        find.text('This only sets your starting workspace.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('workflow-continue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Workspace ready'), findsOneWidget);
  });

  testWidgets('workflow options expose button semantics',
      (WidgetTester tester) async {
    final prefs = PreferencesService(basePath: tempDir.path);
    await prefs.init();
    final appProvider = AppProvider(preferencesService: prefs);
    final semanticsHandle = tester.ensureSemantics();

    await _pumpOnboarding(tester, appProvider);

    final researcherSemantics =
        tester.getSemantics(find.byKey(const Key('workflow-researcher')));
    final hardwareSemantics =
        tester.getSemantics(find.byKey(const Key('workflow-hardware')));

    expect(researcherSemantics.flagsCollection.isButton, isTrue);
    expect(hardwareSemantics.flagsCollection.isButton, isTrue);
    semanticsHandle.dispose();
  });

  testWidgets('workflow options stack on narrow screens',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = PreferencesService(basePath: tempDir.path);
    await prefs.init();
    final appProvider = AppProvider(preferencesService: prefs);
    await _pumpOnboarding(tester, appProvider);

    final researcherTop = tester.getTopLeft(find.text('Neural Researcher'));
    final hardwareTop = tester.getTopLeft(find.text('Hardware Engineer'));

    expect(hardwareTop.dy, greaterThan(researcherTop.dy + 96));
  });
}

Future<void> _pumpOnboarding(
  WidgetTester tester,
  AppProvider appProvider,
) async {
  final router = GoRouter(
    initialLocation: '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/workspace',
        builder: (context, state) =>
            const Scaffold(body: Text('Workspace ready')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appStateProvider.overrideWith((ref) => appProvider),
      ],
      child: ShadApp.router(
        title: 'Onboarding test',
        theme: NmtkShadTheme.light,
        darkTheme: NmtkShadTheme.dark,
        materialThemeBuilder: (_, materialTheme) {
          final isDark = materialTheme.brightness == Brightness.dark;
          return isDark ? AppTheme.darkTheme : AppTheme.lightTheme;
        },
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}
