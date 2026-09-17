import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:neuro_toolkit/features/neurocnl/models/energy_report.dart';
import 'package:neuro_toolkit/features/neurocnl/models/quantization_report.dart';
import 'package:neuro_toolkit/features/neurocnl/models/fault_injection_report.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';

part 'analysis_provider.g.dart';

/// Status for each analysis type.
enum AnalysisStatus { idle, loading, complete, error }

/// State for energy profiling and quantization analysis.
class AnalysisState {
  final AnalysisStatus energyStatus;
  final AnalysisStatus quantizationStatus;
  final AnalysisStatus faultInjectionStatus;
  final EnergyReport? energyReport;
  final QuantizationReport? quantizationReport;
  final FaultInjectionReport? faultInjectionReport;
  final String? energyError;
  final String? quantizationError;
  final String? faultInjectionError;

  const AnalysisState({
    this.energyStatus = AnalysisStatus.idle,
    this.quantizationStatus = AnalysisStatus.idle,
    this.faultInjectionStatus = AnalysisStatus.idle,
    this.energyReport,
    this.quantizationReport,
    this.faultInjectionReport,
    this.energyError,
    this.quantizationError,
    this.faultInjectionError,
  });

  AnalysisState copyWith({
    AnalysisStatus? energyStatus,
    AnalysisStatus? quantizationStatus,
    AnalysisStatus? faultInjectionStatus,
    EnergyReport? energyReport,
    QuantizationReport? quantizationReport,
    FaultInjectionReport? faultInjectionReport,
    String? energyError,
    String? quantizationError,
    String? faultInjectionError,
    bool clearEnergyReport = false,
    bool clearQuantizationReport = false,
    bool clearFaultInjectionReport = false,
    bool clearEnergyError = false,
    bool clearQuantizationError = false,
    bool clearFaultInjectionError = false,
  }) {
    return AnalysisState(
      energyStatus: energyStatus ?? this.energyStatus,
      quantizationStatus: quantizationStatus ?? this.quantizationStatus,
      faultInjectionStatus: faultInjectionStatus ?? this.faultInjectionStatus,
      energyReport: clearEnergyReport
          ? null
          : (energyReport ?? this.energyReport),
      quantizationReport: clearQuantizationReport
          ? null
          : (quantizationReport ?? this.quantizationReport),
      faultInjectionReport: clearFaultInjectionReport
          ? null
          : (faultInjectionReport ?? this.faultInjectionReport),
      energyError: clearEnergyError ? null : (energyError ?? this.energyError),
      quantizationError: clearQuantizationError
          ? null
          : (quantizationError ?? this.quantizationError),
      faultInjectionError: clearFaultInjectionError
          ? null
          : (faultInjectionError ?? this.faultInjectionError),
    );
  }
}

@riverpod
class AnalysisController extends _$AnalysisController {
  @override
  AnalysisState build() => const AnalysisState();

  /// Run energy profiling for the given spec.
  Future<void> runEnergyProfile(String spec) async {
    final api = ref.read(apiClientProvider);

    state = state.copyWith(
      energyStatus: AnalysisStatus.loading,
      clearEnergyReport: true,
      clearEnergyError: true,
    );
    try {
      final report = await api.prostheticEnergy(spec);
      if (!ref.mounted) return;
      state = state.copyWith(
        energyStatus: AnalysisStatus.complete,
        energyReport: report,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        energyStatus: AnalysisStatus.error,
        energyError: 'Energy profiling failed: $e',
      );
    }
  }

  /// Run quantization analysis for the given spec and bit widths.
  Future<void> runQuantization(String spec, List<int> bits) async {
    final api = ref.read(apiClientProvider);

    state = state.copyWith(
      quantizationStatus: AnalysisStatus.loading,
      clearQuantizationReport: true,
      clearQuantizationError: true,
    );
    try {
      final report = await api.prostheticQuantize(spec, bits);
      if (!ref.mounted) return;
      state = state.copyWith(
        quantizationStatus: AnalysisStatus.complete,
        quantizationReport: report,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        quantizationStatus: AnalysisStatus.error,
        quantizationError: 'Quantization analysis failed: $e',
      );
    }
  }

  /// Run fault injection analysis for the given spec and error rate.
  Future<void> runFaultInjection(String spec, double errorRate) async {
    final api = ref.read(apiClientProvider);

    state = state.copyWith(
      faultInjectionStatus: AnalysisStatus.loading,
      clearFaultInjectionReport: true,
      clearFaultInjectionError: true,
    );
    try {
      final report = await api.prostheticFaultInjection(spec, errorRate);
      if (!ref.mounted) return;
      state = state.copyWith(
        faultInjectionStatus: AnalysisStatus.complete,
        faultInjectionReport: report,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        faultInjectionStatus: AnalysisStatus.error,
        faultInjectionError: 'Fault injection analysis failed: $e',
      );
    }
  }

  /// Reset all analysis state.
  void reset() {
    state = const AnalysisState();
  }
}

/// Backward-compat alias.
final analysisProvider = analysisControllerProvider;
