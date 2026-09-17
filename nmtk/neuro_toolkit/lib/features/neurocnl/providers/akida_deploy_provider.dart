import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/deploy_error_formatter.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';

part 'akida_deploy_provider.g.dart';

enum AkidaDeployPhase { idle, validating, ready, unsupported, failed }

class AkidaDeployState {
  final AkidaDeployPhase phase;
  final String supportState;
  final String akidaVersion;
  final String topologyVerdict;
  final List<String> warnings;
  final List<String> rejections;
  final Map<String, dynamic>? networkSummary;
  final Map<String, dynamic>? mappedNetwork;
  final int bitWidth;
  final String hardwareUrl;
  final String? errorMessage;

  const AkidaDeployState({
    this.phase = AkidaDeployPhase.idle,
    this.supportState = 'unsupported',
    this.akidaVersion = 'akida1',
    this.topologyVerdict = 'unknown',
    this.warnings = const [],
    this.rejections = const [],
    this.networkSummary,
    this.mappedNetwork,
    this.bitWidth = 4,
    this.hardwareUrl = '',
    this.errorMessage,
  });

  AkidaDeployState copyWith({
    AkidaDeployPhase? phase,
    String? supportState,
    String? akidaVersion,
    String? topologyVerdict,
    List<String>? warnings,
    List<String>? rejections,
    Map<String, dynamic>? networkSummary,
    Map<String, dynamic>? mappedNetwork,
    int? bitWidth,
    String? hardwareUrl,
    String? errorMessage,
    bool clearSummary = false,
    bool clearMappedNetwork = false,
    bool clearError = false,
  }) {
    return AkidaDeployState(
      phase: phase ?? this.phase,
      supportState: supportState ?? this.supportState,
      akidaVersion: akidaVersion ?? this.akidaVersion,
      topologyVerdict: topologyVerdict ?? this.topologyVerdict,
      warnings: warnings ?? this.warnings,
      rejections: rejections ?? this.rejections,
      networkSummary: clearSummary
          ? null
          : (networkSummary ?? this.networkSummary),
      mappedNetwork: clearMappedNetwork
          ? null
          : (mappedNetwork ?? this.mappedNetwork),
      bitWidth: bitWidth ?? this.bitWidth,
      hardwareUrl: hardwareUrl ?? this.hardwareUrl,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

@riverpod
class AkidaDeployController extends _$AkidaDeployController {
  @override
  AkidaDeployState build() => const AkidaDeployState();

  Future<void> validate(String spec) async {
    if (state.phase == AkidaDeployPhase.validating) {
      return;
    }

    state = state.copyWith(
      phase: AkidaDeployPhase.validating,
      clearSummary: true,
      clearMappedNetwork: true,
      clearError: true,
    );

    final api = ref.read(apiClientProvider);
    try {
      final result = await api.getAkidaDeployability(
        spec,
        bitWidth: state.bitWidth,
        akidaVersion: state.akidaVersion,
      );
      if (!ref.mounted) {
        return;
      }

      final supportState = result['support_state'] as String? ?? 'unsupported';
      state = state.copyWith(
        phase: supportState == 'unsupported'
            ? AkidaDeployPhase.unsupported
            : AkidaDeployPhase.ready,
        supportState: supportState,
        akidaVersion: result['akida_version'] as String? ?? state.akidaVersion,
        topologyVerdict: result['topology_verdict'] as String? ?? 'unknown',
        warnings: _castStringList(result['warnings']),
        rejections: _castStringList(result['rejections']),
        networkSummary: result['network_summary'] as Map<String, dynamic>?,
        mappedNetwork: result['mapped_network'] as Map<String, dynamic>?,
      );
    } on ApiException catch (error) {
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        phase: AkidaDeployPhase.failed,
        errorMessage: formatDeployError(
          error,
          serviceName: 'NeuroStudio',
          action: 'checking Akida exportability',
        ),
      );
    } catch (error) {
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        phase: AkidaDeployPhase.failed,
        errorMessage: formatDeployError(
          error,
          serviceName: 'NeuroStudio',
          action: 'checking Akida exportability',
        ),
      );
    }
  }

  void selectBitWidth(int bitWidth) {
    state = state.copyWith(bitWidth: bitWidth);
  }

  void selectVersion(String akidaVersion) {
    state = state.copyWith(akidaVersion: akidaVersion);
  }

  void setHardwareUrl(String url) {
    state = state.copyWith(hardwareUrl: url);
  }
}

List<String> _castStringList(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  return raw.whereType<String>().toList();
}

/// Backward-compat alias.
final akidaDeployProvider = akidaDeployControllerProvider;
