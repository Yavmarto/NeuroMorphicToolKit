import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurobench/models/benchmark.dart';
import 'package:neuro_toolkit/features/neurobench/models/benchmark_job.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/models/workbench_tab.dart';
import 'package:neuro_toolkit/features/neurobench/models/workspace_route_state.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/providers/execution_provider.dart';
import 'package:neuro_toolkit/features/neurobench/providers/results_provider.dart';

import '../test_helpers.dart';

/// CEL-455 mobile audit: the Execute/Run page's bottom bar (`ActiveJobsBar`),
/// tab bar (`BenchmarkWorkbenchTabs`), and Compare view (`ComparisonWorkspace`)
/// must all stay overflow-free at the minimum supported phone width (375px).
/// These are `RenderFlex overflow` regression guards, mirroring the pattern
/// already used for the neurocnl run step's own 390px checks in
/// `studio_responsive_audit_test.dart`.
void useMinPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

BenchmarkDefinition _testBenchmark() {
  return BenchmarkDefinition(
    id: 'test_bench',
    name: 'Test Benchmark With A Fairly Long Name',
    description: 'A mock benchmark used for mobile overflow regression checks.',
    taskType: 'classification',
    builtin: true,
    assertions: <String>['assertion_1', 'assertion_2'],
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

BenchmarkResult _result(String id, {double accuracy = 0.9}) {
  return BenchmarkResult(
    id: id,
    benchmarkId: 'test_bench',
    networkSpecHash: 'hash-$id',
    timestamp: '2026-04-24T10:00:00Z',
    params: const <String, dynamic>{},
    metrics: {'accuracy': accuracy},
    wallTimeSeconds: 1.2,
    seed: 1,
  );
}

class _RunningJobExecutionController extends BenchmarkExecutionController {
  @override
  BenchmarkExecutionState build() {
    return const BenchmarkExecutionState(
      activeJob: BenchmarkJob(
        id: 'job_a_very_long_identifier_for_wrap_testing',
        benchmarkId: 'test_bench',
        status: BenchmarkJobStatus.running,
        networkPath: 'examples/net.json',
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:01Z',
      ),
    );
  }
}

void main() {
  for (final tab in NeurobenchWorkbenchTab.values) {
    testWidgets(
      '${tab.name} tab renders without overflow at 375px with an active job bar',
      (tester) async {
        useMinPhoneViewport(tester);

        final container = ProviderContainer(
          overrides: [
            benchmarksProvider.overrideWith((ref) async => [_testBenchmark()]),
            resultsProvider.overrideWith((ref) async => [_result('run_1')]),
            baselinesProvider.overrideWith((ref) async => [_result('base_2')]),
            activeBenchmarkResultsProvider.overrideWith(
              (ref) async => [_result('run_1'), _result('base_2')],
            ),
            activeDiffProvider.overrideWith((ref) async => null),
            benchmarkExecutionProvider.overrideWith(
              _RunningJobExecutionController.new,
            ),
          ],
        );
        addTearDown(container.dispose);

        await pumpWorkbenchShell(
          tester,
          container: container,
          routeState: NeurobenchRouteState(
            tab: tab,
            benchmarkId: 'test_bench',
            baselineId: tab == NeurobenchWorkbenchTab.compare ? 'base_2' : null,
            resultId: tab == NeurobenchWorkbenchTab.compare ? 'run_1' : null,
          ),
        );

        // The bottom bar renders expanded by default and stacks the job
        // title above its status label at this width (see active_jobs_bar.dart
        // `isCompact` branch) instead of squeezing both into one Row.
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Compare view stacks export actions and selection badges at 375px',
    (tester) async {
      useMinPhoneViewport(tester);

      final container = ProviderContainer(
        overrides: [
          benchmarksProvider.overrideWith((ref) async => [_testBenchmark()]),
          resultsProvider.overrideWith((ref) async => [_result('run_1')]),
          baselinesProvider.overrideWith((ref) async => [_result('base_2')]),
          activeBenchmarkResultsProvider.overrideWith(
            (ref) async => [_result('run_1'), _result('base_2')],
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

      expect(tester.takeException(), isNull);
      // The Export CSV / Export JSON buttons must both still be reachable —
      // proof they stacked into a Column instead of overflowing a Row.
      expect(find.text('Export CSV'), findsOneWidget);
      expect(find.text('Export JSON'), findsOneWidget);
    },
  );
}
