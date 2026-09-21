import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/providers/results_provider.dart';
import 'package:neuro_toolkit/features/neurobench/models/workspace_route_state.dart';
import 'package:neuro_toolkit/features/neurobench/screens/comparison_screen.dart';
import 'package:neuro_toolkit/features/neurobench/screens/regression_trends_screen.dart';
import 'package:neuro_toolkit/features/neurobench/screens/workbench_shell.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('Initial load smoke test', (WidgetTester tester) async {
    useDesktopViewport(tester);

    final container = ProviderContainer(
      overrides: [
        benchmarksProvider.overrideWith((ref) async => []),
        resultsProvider.overrideWith((ref) async => []),
        baselinesProvider.overrideWith((ref) async => []),
        activeBenchmarkResultsProvider.overrideWith((ref) async => []),
        activeDiffProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: WorkbenchShellScreen(routeState: NeurobenchRouteState()),
        ),
      ),
    );
    await pumpWorkbench(tester);

    expect(find.byType(WorkbenchShellScreen), findsOneWidget);
    expect(find.text('Benchmark Catalog'), findsOneWidget);
    expect(find.text('Select a benchmark'), findsOneWidget);
  });

  testWidgets('Comparison screen exposes explicit back action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ComparisonScreen())),
    );

    expect(find.text('Back to Workbench'), findsOneWidget);
    expect(find.text('Benchmark Comparison'), findsOneWidget);
  });

  testWidgets('Regression trends screen exposes explicit back action', (
    WidgetTester tester,
  ) async {
    // CEL-451: below compactBreakpoint the label shortens to "Back" so the
    // title still fits; this test asserts the wide-layout affordance.
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: RegressionTrendsScreen(benchmarkId: 'demo-bench'),
        ),
      ),
    );

    expect(find.text('Back to Workbench'), findsOneWidget);
    expect(find.text('Trends: demo-bench'), findsOneWidget);
  });
}
