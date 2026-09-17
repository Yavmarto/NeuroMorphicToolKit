import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/sweep.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';

part 'sweep_provider.g.dart';

const _runningSweepStatuses = {'queued', 'running'};

class SweepState {
  final bool isLoading;
  final String? error;
  final SweepResponse? results;
  final BackendSupport? backendSupport;
  final GeneratorFidelitySummary? generatorFidelity;

  SweepState({
    this.isLoading = false,
    this.error,
    this.results,
    this.backendSupport,
    this.generatorFidelity,
  });

  SweepState copyWith({
    bool? isLoading,
    String? error,
    SweepResponse? results,
    BackendSupport? backendSupport,
    bool clearBackendSupport = false,
    GeneratorFidelitySummary? generatorFidelity,
    bool clearGeneratorFidelity = false,
  }) {
    return SweepState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      results: results ?? this.results,
      backendSupport: clearBackendSupport
          ? null
          : (backendSupport ?? this.backendSupport),
      generatorFidelity: clearGeneratorFidelity
          ? null
          : (generatorFidelity ?? this.generatorFidelity),
    );
  }
}

@riverpod
class SweepController extends _$SweepController {
  @override
  SweepState build() => SweepState();

  Future<void> runSweep(SweepRequest request) async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      clearBackendSupport: true,
      clearGeneratorFidelity: true,
    );
    try {
      final apiClient = ref.read(apiClientProvider);
      var response = await apiClient.runSweep(request);
      if (!ref.mounted) return;
      if (response.status == 'failed') {
        state = state.copyWith(
          isLoading: false,
          error: response.error ?? 'Sweep is unsupported for this backend.',
          results: response,
          backendSupport: response.backendSupport,
          generatorFidelity: response.generatorFidelity,
        );
        return;
      }

      final jobId = response.jobId;

      if (jobId != null) {
        for (var attempt = 0; attempt < 30; attempt += 1) {
          if (!_runningSweepStatuses.contains(response.status)) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (!ref.mounted) return;
          response = await apiClient.getSweepStatus(jobId);
          if (!ref.mounted) return;
        }
      }

      if (response.status == 'completed' && response.steps != null) {
        state = state.copyWith(
          isLoading: false,
          results: response,
          backendSupport: response.backendSupport,
          generatorFidelity: response.generatorFidelity,
        );
        return;
      }

      if (_runningSweepStatuses.contains(response.status)) {
        state = state.copyWith(
          isLoading: false,
          error: 'Sweep did not complete in time.',
        );
        return;
      }

      state = state.copyWith(
        isLoading: false,
        error: response.error ?? 'Sweep failed.',
        results: response,
        backendSupport: response.backendSupport,
        generatorFidelity: response.generatorFidelity,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void reset() {
    state = SweepState();
  }
}

/// Backward-compat alias.
final sweepProvider = sweepControllerProvider;
