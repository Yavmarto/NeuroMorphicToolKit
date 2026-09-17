import 'package:neuro_toolkit/features/neurocnl/services/platform_helper.dart' as platform;

import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurochip_handoff.dart';

typedef OriginGetter = String? Function();

enum NeurochipHandoffPreparationStatus {
  unavailable,
  emptySpec,
  deploymentFailed,
  ready,
}

class NeurochipHandoffPreparation {
  const NeurochipHandoffPreparation._({
    required this.status,
    this.target,
    this.errorMessage,
  });

  const NeurochipHandoffPreparation.unavailable()
    : this._(status: NeurochipHandoffPreparationStatus.unavailable);

  const NeurochipHandoffPreparation.emptySpec()
    : this._(status: NeurochipHandoffPreparationStatus.emptySpec);

  const NeurochipHandoffPreparation.deploymentFailed(String message)
    : this._(
        status: NeurochipHandoffPreparationStatus.deploymentFailed,
        errorMessage: message,
      );

  const NeurochipHandoffPreparation.ready(NeurochipHandoffTarget target)
    : this._(status: NeurochipHandoffPreparationStatus.ready, target: target);

  final NeurochipHandoffPreparationStatus status;
  final NeurochipHandoffTarget? target;
  final String? errorMessage;
}

class NeurochipHandoffCoordinator {
  const NeurochipHandoffCoordinator({
    required this.apiClient,
    this.getOrigin = platform.getOrigin,
  });

  final ApiClient apiClient;
  final OriginGetter getOrigin;

  Future<NeurochipHandoffPreparation> prepareTarget({
    required String spec,
    required String targetId,
    required String targetLabel,
    required String destinationWorkspace,
    Map<String, dynamic> readinessSummary = const <String, dynamic>{},
  }) async {
    final origin = getOrigin();
    if (origin == null || origin.isEmpty) {
      return const NeurochipHandoffPreparation.unavailable();
    }
    if (spec.trim().isEmpty) {
      return const NeurochipHandoffPreparation.emptySpec();
    }

    final Map<String, dynamic> networkJson;
    try {
      networkJson = await apiClient.deployToNeurochip(spec);
    } on ApiException catch (e) {
      return NeurochipHandoffPreparation.deploymentFailed(
        _extractErrorMessage(e),
      );
    } on FormatException {
      return const NeurochipHandoffPreparation.deploymentFailed(
        'This spec cannot be deployed to Neurochip. Check validation results.',
      );
    }

    final target = NeurochipHandoff.buildTarget(
      networkJson: networkJson,
      origin: origin,
      targetId: targetId,
      targetLabel: targetLabel,
      destinationWorkspace: destinationWorkspace,
      readinessSummary: readinessSummary,
    );
    if (target == null) {
      return const NeurochipHandoffPreparation.emptySpec();
    }

    return NeurochipHandoffPreparation.ready(target);
  }

  String _extractErrorMessage(ApiException e) {
    return 'This spec cannot be deployed to Neurochip. Check validation results.';
  }
}
