import 'dart:async';
import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:neuro_toolkit/features/neurocnl/models/prosthetic_sim.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';

part 'prosthetic_sim_provider.g.dart';

/// Status of the prosthetic simulation workflow.
enum SimStatus { idle, loading, running, complete, failed }

/// State for prosthetic simulation.
class ProstheticSimState {
  final SimStatus status;
  final ProstheticSimResult? result;
  final String? jobId;
  final String? errorMessage;

  const ProstheticSimState({
    this.status = SimStatus.idle,
    this.result,
    this.jobId,
    this.errorMessage,
  });

  ProstheticSimState copyWith({
    SimStatus? status,
    ProstheticSimResult? result,
    String? jobId,
    String? errorMessage,
    bool clearResult = false,
    bool clearJob = false,
    bool clearError = false,
  }) {
    return ProstheticSimState(
      status: status ?? this.status,
      result: clearResult ? null : (result ?? this.result),
      jobId: clearJob ? null : (jobId ?? this.jobId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

@riverpod
class ProstheticSimController extends _$ProstheticSimController {
  Timer? _pollTimer;
  bool _isPolling = false;

  @override
  ProstheticSimState build() {
    ref.onDispose(() {
      _pollTimer?.cancel();
      _isPolling = false;
    });
    return const ProstheticSimState();
  }

  /// Submit a prosthetic simulation request.
  Future<void> startSimulation(ProstheticSimRequest request) async {
    final api = ref.read(apiClientProvider);

    state = const ProstheticSimState(status: SimStatus.loading);

    try {
      final response = await api.prostheticSimulate(request);
      // Synchronous result – simulation completed immediately.
      state = ProstheticSimState(status: SimStatus.complete, result: response);
    } on ApiException catch (e) {
      if (e.statusCode == 202) {
        // Async job accepted – begin polling.
        final body = jsonDecode(e.body) as Map<String, dynamic>;
        final jobId = body['job_id'] as String;
        state = ProstheticSimState(status: SimStatus.running, jobId: jobId);
        _startPolling(jobId);
      } else {
        state = ProstheticSimState(
          status: SimStatus.failed,
          errorMessage: 'Simulation failed: $e',
        );
      }
    } catch (e) {
      state = ProstheticSimState(
        status: SimStatus.failed,
        errorMessage: 'Simulation failed: $e',
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
      final status = await api.getJobStatus<ProstheticSimResult>(
        jobId,
        fromJsonT: ProstheticSimResult.fromJson,
      );
      if (!ref.mounted) return;

      if (status.status == 'complete') {
        _pollTimer?.cancel();
        state = ProstheticSimState(
          status: SimStatus.complete,
          result: status.result,
        );
      } else if (status.status == 'failed') {
        _pollTimer?.cancel();
        state = ProstheticSimState(
          status: SimStatus.failed,
          errorMessage: status.error ?? 'Job failed',
        );
      }
      // Otherwise keep polling
    } catch (e) {
      if (!ref.mounted) return;
      _pollTimer?.cancel();
      state = ProstheticSimState(
        status: SimStatus.failed,
        errorMessage: 'Polling failed: $e',
      );
    }
  }

  /// Reset state to idle.
  void reset() {
    _pollTimer?.cancel();
    _isPolling = false;
    state = const ProstheticSimState();
  }
}

/// Backward-compat alias.
final prostheticSimProvider = prostheticSimControllerProvider;
