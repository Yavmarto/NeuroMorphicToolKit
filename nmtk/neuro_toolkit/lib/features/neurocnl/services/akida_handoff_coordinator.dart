import 'package:neuro_toolkit/features/neurocnl/services/platform_helper.dart' as platform;

import 'package:neuro_toolkit/features/neurocnl/services/akida_handoff.dart';

typedef OriginGetter = String? Function();

enum AkidaHandoffPreparationStatus { unavailable, mappingUnavailable, ready }

class AkidaHandoffPreparation {
  const AkidaHandoffPreparation._({
    required this.status,
    this.target,
    this.errorMessage,
  });

  const AkidaHandoffPreparation.unavailable()
    : this._(status: AkidaHandoffPreparationStatus.unavailable);

  const AkidaHandoffPreparation.mappingUnavailable(String message)
    : this._(
        status: AkidaHandoffPreparationStatus.mappingUnavailable,
        errorMessage: message,
      );

  const AkidaHandoffPreparation.ready(AkidaHandoffTarget target)
    : this._(status: AkidaHandoffPreparationStatus.ready, target: target);

  final AkidaHandoffPreparationStatus status;
  final AkidaHandoffTarget? target;
  final String? errorMessage;
}

class AkidaHandoffCoordinator {
  const AkidaHandoffCoordinator({this.getOrigin = platform.getOrigin});

  final OriginGetter getOrigin;

  AkidaHandoffPreparation prepareTarget({
    required Map<String, dynamic>? mappedNetwork,
    required int bitWidth,
    required String akidaVersion,
    String supportState = 'unsupported',
    String topologyVerdict = 'unknown',
    Map<String, dynamic>? networkSummary,
    List<String> warnings = const [],
    List<String> rejections = const [],
    String? hardwareUrl,
  }) {
    final origin = getOrigin();
    if (origin == null || origin.isEmpty) {
      return const AkidaHandoffPreparation.unavailable();
    }
    if (mappedNetwork == null || mappedNetwork.isEmpty) {
      return const AkidaHandoffPreparation.mappingUnavailable(
        'Run the Akida check first so Studio can build the mapped-network handoff.',
      );
    }

    final target = AkidaHandoff.buildTarget(
      mappedNetwork: mappedNetwork,
      bitWidth: bitWidth,
      akidaVersion: akidaVersion,
      origin: origin,
      supportState: supportState,
      topologyVerdict: topologyVerdict,
      networkSummary: networkSummary,
      warnings: warnings,
      rejections: rejections,
      hardwareUrl: hardwareUrl,
    );
    if (target == null) {
      return const AkidaHandoffPreparation.mappingUnavailable(
        'Studio could not prepare an Akida handoff target.',
      );
    }

    return AkidaHandoffPreparation.ready(target);
  }
}
