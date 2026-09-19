import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurobench/models/benchmark_job.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_voyager_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurobench/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_voyager_deploy_service.dart';

class _FakeVoyagerService extends StudioVoyagerDeployService {
  _FakeVoyagerService({
    required this.jobSequence,
    required this.result,
    this.submitError,
  }) : super(apiClient: ApiClient(baseUrl: 'http://test'));

  final List<BenchmarkJob> jobSequence;
  final BenchmarkResult result;
  final Object? submitError;

  int fetchCalls = 0;

  @override
  Future<String> submitBenchmark() async {
    if (submitError != null) throw submitError!;
    return 'job-voyager-1';
  }

  @override
  Future<BenchmarkJob> fetchJob(String jobId) async {
    fetchCalls += 1;
    return jobSequence[fetchCalls.clamp(1, jobSequence.length) - 1];
  }

  @override
  Future<BenchmarkResult> fetchResult(String jobId) async => result;
}

BenchmarkJob _job(BenchmarkJobStatus status, {String? error}) {
  return BenchmarkJob(
    id: 'job-voyager-1',
    benchmarkId: StudioVoyagerDeployService.benchmarkId,
    networkPath: '',
    status: status,
    error: error,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
  );
}

BenchmarkResult _result({
  Map<String, double> metrics = const {'cpu_latency_ms': 120.5},
  Map<String, dynamic>? spikeData,
}) {
  return BenchmarkResult(
    id: 'res_voyager_1',
    benchmarkId: StudioVoyagerDeployService.benchmarkId,
    networkSpecHash: 'hash',
    timestamp: '2026-01-01T00:00:00Z',
    targetId: StudioVoyagerDeployService.targetId,
    params: const {},
    metrics: metrics,
    spikeData: spikeData,
    wallTimeSeconds: 42,
    seed: 0,
    metricProvenance: 'on_device',
  );
}

void main() {
  group('StudioVoyagerDeployController', () {
    test('completes with metrics when benchmark job succeeds', () async {
      final fake = _FakeVoyagerService(
        jobSequence: [
          _job(BenchmarkJobStatus.running),
          _job(BenchmarkJobStatus.completed),
        ],
        result: _result(),
      );

      final container = ProviderContainer(
        overrides: [
          studioVoyagerDeployServiceProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      container.listen(studioVoyagerDeployProvider, (_, _) {});

      final notifier = container.read(studioVoyagerDeployProvider.notifier);
      await notifier.runCompileAndBenchmark();

      final state = container.read(studioVoyagerDeployProvider);
      expect(state.phase, StudioVoyagerDeployPhase.completed);
      expect(state.resultMetrics['cpu_latency_ms'], 120.5);
      expect(state.hasCompareableResult, isTrue);
    });

    test('surfaces hardware_pending without placeholder metrics', () async {
      final fake = _FakeVoyagerService(
        jobSequence: [_job(BenchmarkJobStatus.completed)],
        result: _result(
          metrics: const {},
          spikeData: const {'hardware_status': 'pending_hardware'},
        ),
      );

      final container = ProviderContainer(
        overrides: [
          studioVoyagerDeployServiceProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(studioVoyagerDeployProvider.notifier)
          .runCompileAndBenchmark();

      final state = container.read(studioVoyagerDeployProvider);
      expect(state.phase, StudioVoyagerDeployPhase.hardwarePending);
      expect(state.resultMetrics, isEmpty);
      expect(state.hasCompareableResult, isTrue);
    });

    test('marks failed when job errors', () async {
      final fake = _FakeVoyagerService(
        jobSequence: [_job(BenchmarkJobStatus.failed, error: 'compile failed')],
        result: _result(),
      );

      final container = ProviderContainer(
        overrides: [
          studioVoyagerDeployServiceProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(studioVoyagerDeployProvider.notifier)
          .runCompileAndBenchmark();

      final state = container.read(studioVoyagerDeployProvider);
      expect(state.phase, StudioVoyagerDeployPhase.failed);
      expect(state.errorMessage, contains('compile failed'));
    });
  });

  test('benchmarkResultIsHardwarePending reads spike_data flag', () {
    expect(
      benchmarkResultIsHardwarePending(
        _result(spikeData: const {'hardware_status': 'pending_hardware'}),
      ),
      isTrue,
    );
    expect(benchmarkResultIsHardwarePending(_result()), isFalse);
  });
}
