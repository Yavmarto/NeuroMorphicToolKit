import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/deploy_error_formatter.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';

part 'pynq_deploy_provider.g.dart';

enum PynqDeployPhase { idle, validating, ready, unsupported, failed }

class PynqDeployState {
  final PynqDeployPhase phase;
  final PynqSupportState supportState;
  final List<String> warnings;
  final List<String> rejections;
  final Map<String, dynamic>? networkSummary;
  final int bitWidth;
  final String? errorMessage;

  const PynqDeployState({
    this.phase = PynqDeployPhase.idle,
    this.supportState = PynqSupportState.notExportable,
    this.warnings = const [],
    this.rejections = const [],
    this.networkSummary,
    this.bitWidth = 8,
    this.errorMessage,
  });

  PynqDeployState copyWith({
    PynqDeployPhase? phase,
    PynqSupportState? supportState,
    List<String>? warnings,
    List<String>? rejections,
    Map<String, dynamic>? networkSummary,
    int? bitWidth,
    String? errorMessage,
    bool clearSummary = false,
    bool clearError = false,
  }) {
    return PynqDeployState(
      phase: phase ?? this.phase,
      supportState: supportState ?? this.supportState,
      warnings: warnings ?? this.warnings,
      rejections: rejections ?? this.rejections,
      networkSummary: clearSummary
          ? null
          : (networkSummary ?? this.networkSummary),
      bitWidth: bitWidth ?? this.bitWidth,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

@riverpod
class PynqDeployController extends _$PynqDeployController {
  @override
  PynqDeployState build() => const PynqDeployState();

  Future<void> validate(String spec) async {
    if (state.phase == PynqDeployPhase.validating) {
      return;
    }

    state = state.copyWith(
      phase: PynqDeployPhase.validating,
      clearSummary: true,
      clearError: true,
    );

    final api = ref.read(apiClientProvider);
    try {
      final result = await api.getPynqDeployability(
        spec,
        bitWidth: state.bitWidth,
      );
      if (!ref.mounted) {
        return;
      }

      final response = PynqNetworkResponse.fromJson(result);
      state = state.copyWith(
        phase: response.supportState == PynqSupportState.notExportable
            ? PynqDeployPhase.unsupported
            : PynqDeployPhase.ready,
        supportState: response.supportState,
        warnings: response.warnings,
        rejections: response.rejectionReasons,
        networkSummary: response.networkSummary,
      );
    } on ApiException catch (error) {
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        phase: PynqDeployPhase.failed,
        errorMessage: formatDeployError(
          error,
          serviceName: 'NeuroStudio',
          action: 'checking PYNQ-Z2 exportability',
        ),
      );
    } catch (error) {
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        phase: PynqDeployPhase.failed,
        errorMessage: formatDeployError(
          error,
          serviceName: 'NeuroStudio',
          action: 'checking PYNQ-Z2 exportability',
        ),
      );
    }
  }

  void selectBitWidth(int bitWidth) {
    state = state.copyWith(bitWidth: bitWidth);
  }
}
