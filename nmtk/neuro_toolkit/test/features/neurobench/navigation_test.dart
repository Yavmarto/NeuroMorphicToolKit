import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurobench/models/benchmark.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/models/workbench_tab.dart';
import 'package:neuro_toolkit/features/neurobench/models/workspace_route_state.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/providers/results_provider.dart';

import 'test_helpers.dart';

BenchmarkDefinition _testBenchmark() {
  return BenchmarkDefinition(
    id: 'test_bench',
    name: 'Test',
    description: 'A mock benchmark',
    taskType: 'classification',
    builtin: true,
    assertions: <String>[],
    inputSpec: InputSpec(type: 'synthetic'),
    scoring: ScoringConfig(
      primaryMetric: 'accuracy',
      secondaryMetrics: <String>[],
      higherIsBetter: true,
      passThreshold: 0.8,
    ),
    defaultParams: <String, dynamic>{},
  );
}

void main() {
  test('legacy reports path redirects to tab query', () {
    final redirect = legacyWorkbenchRedirectLocation(
      Uri.parse('/reports?benchmarkId=test_bench'),
    );
    expect(redirect, isNotNull);

    final uri = Uri.parse(redirect!);
    expect(uri.path, '/');
    expect(uri.queryParameters['tab'], 'reports');
    expect(uri.queryParameters['benchmarkId'], 'test_bench');
  });

  test('legacy comparison path redirects to compare tab', () {
    final redirect = legacyWorkbenchRedirectLocation(
      Uri.parse('/comparison?benchmarkId=test_bench'),
    );
    expect(redirect, isNotNull);
    expect(
      NeurobenchRouteState.fromUri(Uri.parse(redirect!)).tab,
      NeurobenchWorkbenchTab.compare,
    );
  });

  testWidgets('Reports tab shows report workbench when benchmark selected', (
    tester,
  ) async {
    useDesktopViewport(tester);

    final container = ProviderContainer(
      overrides: [
        benchmarksProvider.overrideWith((ref) async => [_testBenchmark()]),
        resultsProvider.overrideWith((ref) async => <BenchmarkResult>[]),
        baselinesProvider.overrideWith((ref) async => <BenchmarkResult>[]),
        activeBenchmarkResultsProvider.overrideWith((ref) async => []),
        activeDiffProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);

    await pumpWorkbenchShell(
      tester,
      container: container,
      routeState: const NeurobenchRouteState(
        tab: NeurobenchWorkbenchTab.reports,
        benchmarkId: 'test_bench',
      ),
    );

    expect(find.text('Report Workbench'), findsOneWidget);
  });

  testWidgets('Comparison tab shows baseline and result selectors', (
    tester,
  ) async {
    useDesktopViewport(tester);

    final container = ProviderContainer(
      overrides: [
        benchmarksProvider.overrideWith((ref) async => [_testBenchmark()]),
        resultsProvider.overrideWith(
          (ref) async => [
            BenchmarkResult(
              id: 'run_1',
              benchmarkId: 'test_bench',
              networkSpecHash: 'hash-1',
              timestamp: '2026-04-24T10:00:00Z',
              params: const <String, dynamic>{},
              metrics: const {'accuracy': 0.92},
              wallTimeSeconds: 1.2,
              seed: 1,
            ),
          ],
        ),
        baselinesProvider.overrideWith(
          (ref) async => [
            BenchmarkResult(
              id: 'base_2',
              benchmarkId: 'test_bench',
              networkSpecHash: 'hash-0',
              timestamp: '2026-04-23T10:00:00Z',
              params: const <String, dynamic>{},
              metrics: const {'accuracy': 0.88},
              wallTimeSeconds: 1.1,
              seed: 2,
            ),
          ],
        ),
        activeBenchmarkResultsProvider.overrideWith(
          (ref) async => [
            BenchmarkResult(
              id: 'run_1',
              benchmarkId: 'test_bench',
              networkSpecHash: 'hash-1',
              timestamp: '2026-04-24T10:00:00Z',
              params: const <String, dynamic>{},
              metrics: const {'accuracy': 0.92},
              wallTimeSeconds: 1.2,
              seed: 1,
            ),
          ],
        ),
        activeDiffProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);

    await pumpWorkbenchShell(
      tester,
      container: container,
      routeState: const NeurobenchRouteState(
        tab: NeurobenchWorkbenchTab.compare,
        benchmarkId: 'test_bench',
        baselineId: 'base_2',
        resultId: 'run_1',
      ),
    );

    await tester.tap(find.text('Comparisons'));
    await pumpWorkbench(tester);

    expect(find.text('Platform Comparison'), findsWidgets);
    expect(find.text('base_2'), findsWidgets);
    expect(find.text('run_1'), findsWidgets);
  });
}
