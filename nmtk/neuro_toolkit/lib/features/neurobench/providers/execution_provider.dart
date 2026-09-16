import 'dart:async';
import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurobench/models/benchmark.dart';
import 'package:neuro_toolkit/features/neurobench/models/benchmark_job.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/providers/results_provider.dart';

part 'execution_provider.g.dart';

class BenchmarkExecutionState {
  const BenchmarkExecutionState({
    this.draft = const BenchmarkRunDraft(),
    this.activeJob,
    this.submitting = false,
    this.cancelling = false,
    this.errorMessage,
    this.noticeMessage,
  });

  final BenchmarkRunDraft draft;
  final BenchmarkJob? activeJob;
  final bool submitting;
  final bool cancelling;
  final String? errorMessage;
  final String? noticeMessage;

  bool get hasActiveBackgroundJob =>
      activeJob != null && !activeJob!.status.isTerminal;

  BenchmarkExecutionState copyWith({
    BenchmarkRunDraft? draft,
    BenchmarkJob? activeJob,
    bool clearActiveJob = false,
    bool? submitting,
    bool? cancelling,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? noticeMessage,
    bool clearNoticeMessage = false,
  }) {
    return BenchmarkExecutionState(
      draft: draft ?? this.draft,
      activeJob: clearActiveJob ? null : activeJob ?? this.activeJob,
      submitting: submitting ?? this.submitting,
      cancelling: cancelling ?? this.cancelling,
      errorMessage:
          clearErrorMessage ? null : errorMessage ?? this.errorMessage,
      noticeMessage:
          clearNoticeMessage ? null : noticeMessage ?? this.noticeMessage,
    );
  }
}

@riverpod
class BenchmarkExecutionController extends _$BenchmarkExecutionController {
  @override
  BenchmarkExecutionState build() {
    _trackedJobId = ref.read(activeJobIdProvider);
    final activeBenchmark = ref.read(activeBenchmarkProvider);

    // build() must never read `state` while it's being computed — Riverpod
    // throws "Tried to read the state of an uninitialized provider" if it
    // does. Compute the initial draft locally instead of going through
    // `_resetDraft`, which assigns to `state`.
    var initialState = const BenchmarkExecutionState();
    if (activeBenchmark != null) {
      _draftBenchmarkId = activeBenchmark.id;
      initialState = initialState.copyWith(
        draft: BenchmarkRunDraft.fromDefaults(
          benchmarkId: activeBenchmark.id,
          defaultParams: activeBenchmark.defaultParams,
        ),
      );
    }
    if (_trackedJobId != null) {
      unawaited(_refreshJob(_trackedJobId!, startPolling: true));
    }

    ref.onDispose(() => _stopPolling());

    ref.listen<BenchmarkDefinition?>(
      activeBenchmarkProvider,
      (_, next) => syncBenchmark(next),
    );
    ref.listen<String?>(activeJobIdProvider, (_, next) => syncTrackedJob(next));

    return initialState;
  }

  Timer? _pollTimer;
  String? _draftBenchmarkId;
  String? _trackedJobId;
  int _pollFailures = 0;

  void syncBenchmark(BenchmarkDefinition? benchmark) {
    if (benchmark == null || _draftBenchmarkId == benchmark.id) {
      return;
    }
    _resetDraft(benchmark);
  }

  void syncTrackedJob(String? jobId) {
    if (_trackedJobId == jobId) {
      return;
    }
    _trackedJobId = jobId;
    _pollFailures = 0;
    _pollTimer?.cancel();
    if (jobId == null || jobId.isEmpty) {
      state = state.copyWith(clearActiveJob: true);
      return;
    }
    unawaited(_refreshJob(jobId, startPolling: true));
  }

  void updateNetworkPath(String value) {
    state = state.copyWith(
      draft: state.draft.copyWith(networkPath: value),
      clearErrorMessage: true,
      clearNoticeMessage: true,
    );
  }

  void updateSeedText(String value) {
    state = state.copyWith(
      draft: state.draft.copyWith(seedText: value),
      clearErrorMessage: true,
      clearNoticeMessage: true,
    );
  }

  void updateTarget(String value) {
    state = state.copyWith(
      draft: state.draft.copyWith(target: value),
      clearErrorMessage: true,
      clearNoticeMessage: true,
    );
  }

  void updateParamsText(String value) {
    state = state.copyWith(
      draft: state.draft.copyWith(paramsText: value),
      clearErrorMessage: true,
      clearNoticeMessage: true,
    );
  }

  void clearMessages() {
    state = state.copyWith(clearErrorMessage: true, clearNoticeMessage: true);
  }

  Future<bool> submitRun(BenchmarkDefinition benchmark) async {
    if (state.submitting || state.hasActiveBackgroundJob) {
      return false;
    }

    final validationError = _validateDraft();
    if (validationError != null) {
      state = state.copyWith(errorMessage: validationError);
      return false;
    }

    final request = _buildRunRequest(benchmark);
    if (request == null) {
      state = state.copyWith(
        errorMessage: 'The run draft is invalid. Check seed and params JSON.',
      );
      return false;
    }

    state = state.copyWith(
      submitting: true,
      clearErrorMessage: true,
      clearNoticeMessage: true,
    );

    try {
      final jobId =
          await ref.read(apiClientProvider).submitBenchmarkRun(request);
      ref.read(activeJobIdProvider.notifier).set(jobId);
      _trackedJobId = jobId;
      await _refreshJob(jobId, startPolling: true);
      state = state.copyWith(
        submitting: false,
        noticeMessage: 'Benchmark queued as $jobId',
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        submitting: false,
        errorMessage: 'Unable to queue benchmark run: $error',
      );
      return false;
    }
  }

  Future<void> cancelActiveJob() async {
    final job = state.activeJob;
    if (job == null || job.status.isTerminal || state.cancelling) {
      return;
    }

    state = state.copyWith(cancelling: true, clearErrorMessage: true);
    try {
      await ref.read(apiClientProvider).cancelBenchmarkRun(job.id);
      await _refreshJob(job.id);
      state = state.copyWith(
        cancelling: false,
        noticeMessage: 'Cancelled ${job.id}',
      );
    } catch (error) {
      state = state.copyWith(
        cancelling: false,
        errorMessage: 'Unable to cancel ${job.id}: $error',
      );
    }
  }

  void _resetDraft(BenchmarkDefinition benchmark) {
    _draftBenchmarkId = benchmark.id;
    state = state.copyWith(
      draft: BenchmarkRunDraft.fromDefaults(
        benchmarkId: benchmark.id,
        defaultParams: benchmark.defaultParams,
      ),
      clearErrorMessage: true,
      clearNoticeMessage: true,
    );
  }

  String? _validateDraft() {
    final networkPath = state.draft.networkPath.trim();
    if (networkPath.isEmpty) {
      return 'Network path is required before submitting a benchmark run.';
    }

    final seedText = state.draft.seedText.trim();
    if (seedText.isNotEmpty && int.tryParse(seedText) == null) {
      return 'Seed must be an integer.';
    }

    final paramsText = state.draft.paramsText.trim();
    if (paramsText.isNotEmpty) {
      try {
        final decoded = jsonDecode(paramsText);
        if (decoded is! Map<String, dynamic>) {
          return 'Params JSON must decode to an object.';
        }
      } catch (_) {
        return 'Params must be valid JSON.';
      }
    }

    return null;
  }

  BenchmarkRunRequest? _buildRunRequest(BenchmarkDefinition benchmark) {
    final validationError = _validateDraft();
    if (validationError != null) {
      return null;
    }

    final seedText = state.draft.seedText.trim();
    final paramsText = state.draft.paramsText.trim();
    final params = paramsText.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(
            jsonDecode(paramsText) as Map<String, dynamic>,
          );

    return BenchmarkRunRequest(
      benchmarkId: benchmark.id,
      networkPath: state.draft.networkPath.trim(),
      params: params,
      seed: seedText.isEmpty ? null : int.parse(seedText),
      target: state.draft.target.trim().isEmpty
          ? 'simulation'
          : state.draft.target.trim(),
    );
  }

  Future<void> _refreshJob(String jobId, {bool startPolling = false}) async {
    try {
      final job = await ref.read(apiClientProvider).getBenchmarkJob(jobId);
      _pollFailures = 0;
      state = state.copyWith(activeJob: job, clearErrorMessage: true);

      if (job.status == BenchmarkJobStatus.completed && job.resultId != null) {
        _stopPolling();
        ref.read(selectedResultIdProvider.notifier).set(job.resultId);
        ref.invalidate(activeBenchmarkResultsProvider);
        ref.invalidate(resultsProvider);
        ref.invalidate(baselinesProvider);
      } else if (job.status.isTerminal) {
        _stopPolling();
      } else if (startPolling) {
        _startPolling(jobId);
      }
    } catch (error) {
      _pollFailures++;
      if (_pollFailures >= 3) {
        _pollFailures = 0;
        _stopPolling();
        state = state.copyWith(
          clearActiveJob: true,
          errorMessage: 'Lost contact with benchmark backend — job cleared.',
        );
      } else {
        state = state.copyWith(
          errorMessage: 'Unable to refresh benchmark job $jobId: $error',
        );
      }
    }
  }

  void _startPolling(String jobId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshJob(jobId));
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}

final benchmarkExecutionProvider = benchmarkExecutionControllerProvider;
