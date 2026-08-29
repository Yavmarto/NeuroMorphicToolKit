import 'dart:async';
import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/sleep_train.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';

part 'learning_provider.g.dart';

/// Status of sleep-training workflow.
enum TrainingStatus { idle, training, complete, failed }

/// State for sleep training (offline learning).
class LearningState {
  final TrainingStatus status;
  final SleepTrainResult? result;
  final String? jobId;
  final String? errorMessage;

  const LearningState({
    this.status = TrainingStatus.idle,
    this.result,
    this.jobId,
    this.errorMessage,
  });

  LearningState copyWith({
    TrainingStatus? status,
    SleepTrainResult? result,
    String? jobId,
    String? errorMessage,
    bool clearResult = false,
    bool clearJob = false,
    bool clearError = false,
  }) {
    return LearningState(
      status: status ?? this.status,
      result: clearResult ? null : (result ?? this.result),
      jobId: clearJob ? null : (jobId ?? this.jobId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

@riverpod
class LearningController extends _$LearningController {
  Timer? _pollTimer;
  bool _isPolling = false;

  @override
  LearningState build() {
    ref.onDispose(() {
      _pollTimer?.cancel();
    });
    return const LearningState();
  }

  /// Submit a sleep-training request.
  Future<void> startTraining(SleepTrainRequest request) async {
    final api = ref.read(apiClientProvider);

    state = const LearningState(status: TrainingStatus.training);

    try {
      final response = await api.prostheticSleep(request);
      // Synchronous result – training completed immediately.
      state = LearningState(status: TrainingStatus.complete, result: response);
    } on ApiException catch (e) {
      if (e.statusCode == 202) {
        // Async job accepted – begin polling.
        final body = jsonDecode(e.body) as Map<String, dynamic>;
        final jobId = body['job_id'] as String;
        state = LearningState(status: TrainingStatus.training, jobId: jobId);
        _startPolling(jobId);
      } else {
        state = LearningState(
          status: TrainingStatus.failed,
          errorMessage: 'Training failed: $e',
        );
      }
    } catch (e) {
      state = LearningState(
        status: TrainingStatus.failed,
        errorMessage: 'Training failed: $e',
      );
    }
  }

  void _startPolling(String jobId) {
    _pollTimer?.cancel();
    _isPolling = false;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_isPolling) return;
      _isPolling = true;
      try {
        await _pollJob(jobId);
      } finally {
        _isPolling = false;
      }
    });
  }

  Future<void> _pollJob(String jobId) async {
    if (!ref.mounted) {
      _pollTimer?.cancel();
      return;
    }

    final api = ref.read(apiClientProvider);
    try {
      final status = await api.getJobStatus<SleepTrainResult>(
        jobId,
        fromJsonT: SleepTrainResult.fromJson,
      );
      if (!ref.mounted) return;

      if (status.status == 'complete') {
        _pollTimer?.cancel();
        state = LearningState(
          status: TrainingStatus.complete,
          result: status.result,
        );
      } else if (status.status == 'failed') {
        _pollTimer?.cancel();
        state = LearningState(
          status: TrainingStatus.failed,
          errorMessage: status.error ?? 'Training job failed',
        );
      }
    } catch (e) {
      if (!ref.mounted) return;
      _pollTimer?.cancel();
      state = LearningState(
        status: TrainingStatus.failed,
        errorMessage: 'Polling failed: $e',
      );
    }
  }

  /// Reset state to idle.
  void reset() {
    _pollTimer?.cancel();
    state = const LearningState();
  }
}

/// Backward-compat alias.
final learningProvider = learningControllerProvider;
