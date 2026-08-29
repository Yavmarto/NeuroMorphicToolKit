import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:neuro_toolkit/features/neurocnl/models/crossbar_export.dart';
import 'package:neuro_toolkit/features/neurocnl/models/crossbar_export_result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';

part 'export_provider.g.dart';

/// Status for crossbar export workflow.
enum ExportStatus { idle, exporting, complete, error }

/// State for crossbar export.
class ExportState {
  final ExportStatus status;
  final CrossbarExportResult? result;
  final String? errorMessage;

  const ExportState({
    this.status = ExportStatus.idle,
    this.result,
    this.errorMessage,
  });

  ExportState copyWith({
    ExportStatus? status,
    CrossbarExportResult? result,
    String? errorMessage,
    bool clearResult = false,
    bool clearError = false,
  }) {
    return ExportState(
      status: status ?? this.status,
      result: clearResult ? null : (result ?? this.result),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

@riverpod
class ExportController extends _$ExportController {
  @override
  ExportState build() => const ExportState();

  /// Export a crossbar mapping from learned weights.
  Future<void> exportCrossbar(CrossbarExportRequest request) async {
    final api = ref.read(apiClientProvider);

    state = const ExportState(status: ExportStatus.exporting);
    try {
      final response = await api.prostheticExportCrossbar(request);
      if (!ref.mounted) return;
      state = ExportState(status: ExportStatus.complete, result: response);
    } catch (e) {
      if (!ref.mounted) return;
      state = ExportState(
        status: ExportStatus.error,
        errorMessage: 'Export failed: $e',
      );
    }
  }

  /// Reset state to idle.
  void reset() {
    state = const ExportState();
  }
}

/// Backward-compat alias.
final exportProvider = exportControllerProvider;
