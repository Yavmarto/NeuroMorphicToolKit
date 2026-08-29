// ignore_for_file: override_on_non_overriding_member
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurobench/models/benchmark.dart';
import 'package:neuro_toolkit/features/neurobench/models/workbench_tab.dart';
import 'package:neuro_toolkit/features/neurobench/models/workspace_route_state.dart';
import 'package:neuro_toolkit/features/neurobench/models/benchmark_job.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/providers/results_provider.dart';
import 'package:neuro_toolkit/features/neurobench/services/api_client.dart';

import 'test_helpers.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({
    required this.benchmarks,
    required this.results,
    required this.baselines,
  }) : super(baseUrl: 'http://localhost:8003');

  final List<BenchmarkDefinition> benchmarks;
  final List<BenchmarkResult> results;
  final List<BenchmarkResult> baselines;
  final List<BenchmarkRunRequest> submittedRequests = [];
  final Map<String, List<BenchmarkJob>> jobResponses = {};
  final Map<String, BenchmarkResult> jobResults = {};
  final Map<String, int> _jobIndexes = {};

  @override
  Future<List<BenchmarkDefinition>> getBenchmarks() async => benchmarks;

  @override
  Future<List<BenchmarkResult>> getResults() async => results;

  @override
  Future<List<BenchmarkResult>> getBaselines() async => baselines;

  @override
  Future<String> submitBenchmarkRun(BenchmarkRunRequest request) async {
    submittedRequests.add(request);
    return 'job_queued';
  }

  @override
  Future<BenchmarkJob> getBenchmarkJob(String jobId) async {
    final responses = jobResponses[jobId];
    if (responses == null || responses.isEmpty) {
      throw Exception('Unknown job: $jobId');
    }

    final nextIndex = _jobIndexes.putIfAbsent(jobId, () => 0);
    final job = responses[
        nextIndex < responses.length ? nextIndex : responses.length - 1];
    if (nextIndex < responses.length - 1) {
      _jobIndexes[jobId] = nextIndex + 1;
    }

    if (job.status == BenchmarkJobStatus.completed && job.resultId != null) {
      final result = jobResults[job.resultId!];
      if (result != null && !results.any((item) => item.id == result.id)) {
        results.add(result);
      }
    }

    return job;
  }

  @override
  Future<bool> cancelBenchmarkRun(String jobId) async {
    jobResponses[jobId] = [
      BenchmarkJob(
        id: jobId,
        benchmarkId: 'test_bench',
        networkPath: 'examples/test_bench.json',
        status: BenchmarkJobStatus.cancelled,
        createdAt: '2026-04-24T10:00:00Z',
        updatedAt: '2026-04-24T10:05:00Z',
      ),
    ];
    return true;
  }
}

BenchmarkDefinition _benchmark() {
  return BenchmarkDefinition(
    id: 'test_bench',
    name: 'Test Benchmark',
    description: 'A benchmark used for execution flow tests.',
    taskType: 'classification',
    builtin: true,
    assertions: const ['assert accuracy > 0.8'],
    inputSpec: InputSpec(type: 'synthetic'),
    scoring: ScoringConfig(
      primaryMetric: 'accuracy',
      secondaryMetrics: const ['latency_ms'],
      higherIsBetter: true,
      passThreshold: 0.8,
    ),
    defaultParams: const {
      'network_path': 'examples/test_bench.json',
      'seed': 7,
      'batch_size': 4,
    },
  );
}

BenchmarkResult _result() {
  return BenchmarkResult(
    id: 'run_1',
    benchmarkId: 'test_bench',
    networkSpecHash: 'hash-1',
    timestamp: '2026-04-24T10:05:00Z',
    params: const {'batch_size': 4},
    metrics: const {'accuracy': 0.93},
    wallTimeSeconds: 1.5,
    seed: 7,
  );
}

BenchmarkJob _job({required BenchmarkJobStatus status, String? resultId}) {
  return BenchmarkJob(
    id: 'job_queued',
    benchmarkId: 'test_bench',
    networkPath: 'examples/test_bench.json',
    params: const {'batch_size': 4},
    seed: 7,
    status: status,
    resultId: resultId,
    createdAt: '2026-04-24T10:00:00Z',
    updatedAt: '2026-04-24T10:05:00Z',
  );
}

void main() {
  testWidgets('queues a benchmark job and tracks background completion', (
    WidgetTester tester,
  ) async {
    useDesktopViewport(tester);

    final fakeApi = _FakeApiClient(
      benchmarks: [_benchmark()],
      results: <BenchmarkResult>[],
      baselines: <BenchmarkResult>[],
    );
    fakeApi.jobResponses['job_queued'] = [
      _job(status: BenchmarkJobStatus.running),
      _job(status: BenchmarkJobStatus.completed, resultId: 'run_1'),
    ];
    fakeApi.jobResults['run_1'] = _result();

    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(fakeApi),
        benchmarksProvider.overrideWith((ref) async => fakeApi.benchmarks),
        resultsProvider.overrideWith((ref) async => fakeApi.results),
        baselinesProvider.overrideWith((ref) async => fakeApi.baselines),
        activeBenchmarkResultsProvider.overrideWith(
          (ref) async => fakeApi.results,
        ),
        activeDiffProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);

    await pumpWorkbenchShell(
      tester,
      container: container,
      routeState: const NeurobenchRouteState(benchmarkId: 'test_bench'),
    );

    expect(find.text('Run Benchmark'), findsOneWidget);
    await tester.tap(find.text('Run Benchmark'));
    await pumpWorkbench(tester);

    expect(fakeApi.submittedRequests, hasLength(1));
    expect(
      fakeApi.submittedRequests.single.networkPath,
      'examples/test_bench.json',
    );
    expect(find.textContaining('job_queued'), findsWidgets);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('run_1'), findsWidgets);

    container.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('restores an in-flight job from a deep link', (
    WidgetTester tester,
  ) async {
    useDesktopViewport(tester);

    final fakeApi = _FakeApiClient(
      benchmarks: [_benchmark()],
      results: <BenchmarkResult>[],
      baselines: <BenchmarkResult>[],
    );
    fakeApi.jobResponses['job_restore'] = [
      const BenchmarkJob(
        id: 'job_restore',
        benchmarkId: 'test_bench',
        networkPath: 'examples/test_bench.json',
        status: BenchmarkJobStatus.running,
        createdAt: '2026-04-24T10:00:00Z',
        updatedAt: '2026-04-24T10:02:00Z',
      ),
    ];

    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(fakeApi),
        benchmarksProvider.overrideWith((ref) async => fakeApi.benchmarks),
        resultsProvider.overrideWith((ref) async => fakeApi.results),
        baselinesProvider.overrideWith((ref) async => fakeApi.baselines),
        activeBenchmarkResultsProvider.overrideWith(
          (ref) async => fakeApi.results,
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
        jobId: 'job_restore',
      ),
    );
    await pumpWorkbench(tester);

    expect(find.textContaining('job_restore'), findsWidgets);
    expect(find.text('Running'), findsOneWidget);

    container.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
