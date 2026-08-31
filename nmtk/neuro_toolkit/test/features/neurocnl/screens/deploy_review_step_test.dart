// The Review step (`deployReview`) owns every deploy target's results. These
// pin the two things that are easy to get wrong when results move out of the
// Deploy step: the per-target dispatch, and what the step says when the
// selected target has produced nothing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;
import 'package:mockito/mockito.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/deploy_results_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/studio_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers_test.mocks.dart';

Future<ProviderContainer> _pumpReviewStep(
  WidgetTester tester, {
  required MockApiClient mockApi,
  required String target,
  List<Override> overrides = const <Override>[],
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(mockApi), ...overrides],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: StudioScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final container = ProviderScope.containerOf(
    tester.element(find.byType(StudioScreen)),
  );
  container.read(workspaceProvider.notifier)
    ..setSelectedDeployTarget(target)
    ..setActivePipelineStep('deployReview');
  // Two pumps: the stage area jumps pages in a post-frame callback.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return container;
}

void main() {
  late MockApiClient mockApi;

  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
    mockApi = MockApiClient();
    when(mockApi.getTemplates()).thenAnswer((_) async => const []);
  });

  testWidgets('empty state explains how to produce a result', (
    WidgetTester tester,
  ) async {
    await _pumpReviewStep(tester, mockApi: mockApi, target: 'lava');

    expect(tester.takeException(), isNull);
    expect(find.text('No Lava / Loihi2 results yet.'), findsOneWidget);
    expect(
      find.textContaining('Run this target in the Deploy step'),
      findsOneWidget,
    );
    expect(find.text('Back to Deploy'), findsNothing);
  });

  testWidgets('a codegen-only target says so instead of promising results', (
    WidgetTester tester,
  ) async {
    await _pumpReviewStep(tester, mockApi: mockApi, target: 'brian2');

    expect(tester.takeException(), isNull);
    expect(find.textContaining('produces no run results'), findsOneWidget);
  });

  testWidgets('offers the targets that do hold results', (
    WidgetTester tester,
  ) async {
    await _pumpReviewStep(
      tester,
      mockApi: mockApi,
      target: 'lava',
      overrides: [
        deployTargetHasResultProvider('pynq').overrideWithValue(true),
      ],
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Results are available for:'), findsOneWidget);
    expect(find.text('PYNQ-Z2'), findsOneWidget);

    // Tapping it switches the selected target so its results render.
    await tester.tap(find.text('PYNQ-Z2'));
    await tester.pumpAndSettle();
    expect(find.text('No PYNQ-Z2 results yet.'), findsNothing);
    expect(find.text('PYNQ-Z2'), findsWidgets);
  });

  testWidgets('dropdown greys out targets with no result yet', (
    WidgetTester tester,
  ) async {
    await _pumpReviewStep(tester, mockApi: mockApi, target: 'lava');

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();

    final notRunItem = find.text('Akida (not run yet)');
    expect(notRunItem, findsOneWidget);

    // Disabled items don't respond to tap — selection stays on 'lava'.
    await tester.tap(notRunItem);
    await tester.pumpAndSettle();
    expect(find.text('No Lava / Loihi2 results yet.'), findsOneWidget);
  });

  testWidgets('compare mode renders two targets side by side', (
    WidgetTester tester,
  ) async {
    await _pumpReviewStep(
      tester,
      mockApi: mockApi,
      target: 'lava',
      overrides: [
        deployTargetHasResultProvider('lava').overrideWithValue(true),
        deployTargetHasResultProvider('pynq').overrideWithValue(true),
      ],
    );

    await tester.tap(find.widgetWithText(FilterChip, 'Compare'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Lava / Loihi2'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'PYNQ-Z2'));
    await tester.tap(find.widgetWithText(ZetaButton, 'Compare'));
    await tester.pumpAndSettle();

    expect(find.text('Comparing 2'), findsOneWidget);
    expect(find.text('Lava / Loihi2'), findsWidgets);
    expect(find.text('PYNQ-Z2'), findsWidgets);
  });
}
