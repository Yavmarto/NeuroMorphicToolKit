import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurobench/models/benchmark_job.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_voyager_deploy_service.dart';

part 'studio_voyager_deploy_provider.g.dart';

enum StudioVoyagerDeployPhase {
  idle,
  running,
  completed,
  hardwarePending,
  failed,
}

class StudioVoyagerDeployState {
  const StudioVoyagerDeployState({
    this.phase = StudioVoyagerDeployPhase.idle,
    this.activeJob,
    this.result,
    this.activityMessage,
    this.errorMessage,
  });

  final StudioVoyagerDeployPhase phase;
  final BenchmarkJob? activeJob;
  final BenchmarkResult? result;
  final String? activityMessage;
  final String? errorMessage;

  bool get isBusy => phase == StudioVoyagerDeployPhase.running;

  bool get hasCompareableResult =>
      result != null &&
      (phase == StudioVoyagerDeployPhase.completed ||
          phase == StudioVoyagerDeployPhase.hardwarePending);

  Map<String, double> get resultMetrics => result?.metrics ?? const {};

  StudioVoyagerDeployState copyWith({
    StudioVoyagerDeployPhase? phase,
    BenchmarkJob? activeJob,
    bool clearActiveJob = false,
    BenchmarkResult? result,
    bool clearResult = false,
    String? activityMessage,
    bool clearActivityMessage = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return StudioVoyagerDeployState(
      phase: phase ?? this.phase,
      activeJob: clearActiveJob ? null : activeJob ?? this.activeJob,
      result: clearResult ? null : result ?? this.result,
      activityMessage: clearActivityMessage
          ? null
          : activityMessage ?? this.activityMessage,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

@riverpod
class StudioVoyagerDeployController extends _$StudioVoyagerDeployController {
  StudioVoyagerDeployService get _service =>
      ref.read(studioVoyagerDeployServiceProvider);

  @override
  StudioVoyagerDeployState build() => const StudioVoyagerDeployState();

  Future<void> runCompileAndBenchmark() async {
    if (state.isBusy) return;

    state = state.copyWith(
      phase: StudioVoyagerDeployPhase.running,
      clearResult: true,
      clearActiveJob: true,
      activityMessage: 'Compiling YOLOv8n for Axelera Voyager…',
      clearErrorMessage: true,
    );

    try {
      final jobId = await _service.submitBenchmark();
      if (!ref.mounted) return;

      var job = await _service.fetchJob(jobId);
      while (!job.status.isTerminal) {
        if (!ref.mounted) return;
        state = state.copyWith(
          activeJob: job,
          activityMessage: job.status == BenchmarkJobStatus.running
              ? 'Benchmarking CPU vs AIPU latency…'
              : 'Queued Voyager compile+benchmark…',
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        job = await _service.fetchJob(jobId);
      }

      if (!ref.mounted) return;
      if (job.status == BenchmarkJobStatus.failed) {
        state = state.copyWith(
          phase: StudioVoyagerDeployPhase.failed,
          activeJob: job,
          errorMessage: job.error ?? 'Voyager compile+benchmark failed.',
        );
        return;
      }
      if (job.status == BenchmarkJobStatus.cancelled) {
        state = state.copyWith(
          phase: StudioVoyagerDeployPhase.idle,
          activeJob: job,
          activityMessage: 'Run cancelled.',
        );
        return;
      }

      final result = await _service.fetchResult(jobId);
      if (!ref.mounted) return;

      final hardwarePending = benchmarkResultIsHardwarePending(result);
      state = state.copyWith(
        phase: hardwarePending
            ? StudioVoyagerDeployPhase.hardwarePending
            : StudioVoyagerDeployPhase.completed,
        activeJob: job,
        result: result,
        activityMessage: hardwarePending
            ? 'Compile finished; AIPU numbers need Metis hardware.'
            : 'Voyager compile+benchmark finished. Open Compare to diff targets.',
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: StudioVoyagerDeployPhase.failed,
        errorMessage: error.toString(),
      );
    }
  }
}

/// Backward-compat alias.
final studioVoyagerDeployProvider = studioVoyagerDeployControllerProvider;
