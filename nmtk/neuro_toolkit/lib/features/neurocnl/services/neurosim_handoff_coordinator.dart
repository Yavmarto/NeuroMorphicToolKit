import 'package:neuro_toolkit/features/neurocnl/services/platform_helper.dart' as platform;

import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurosim_handoff.dart';

typedef OriginGetter = String? Function();

enum NeurosimHandoffPreparationStatus { unavailable, emptySpec, ready }

class NeurosimHandoffPreparation {
  const NeurosimHandoffPreparation._({required this.status, this.target});

  const NeurosimHandoffPreparation.unavailable()
    : this._(status: NeurosimHandoffPreparationStatus.unavailable);

  const NeurosimHandoffPreparation.emptySpec()
    : this._(status: NeurosimHandoffPreparationStatus.emptySpec);

  const NeurosimHandoffPreparation.ready(NeurosimHandoffTarget target)
    : this._(status: NeurosimHandoffPreparationStatus.ready, target: target);

  final NeurosimHandoffPreparationStatus status;
  final NeurosimHandoffTarget? target;
}

class NeurosimHandoffCoordinator {
  const NeurosimHandoffCoordinator({
    required this.apiClient,
    this.getOrigin = platform.getOrigin,
  });

  final ApiClient apiClient;
  final OriginGetter getOrigin;

  Future<NeurosimHandoffPreparation> prepareTarget({
    required String spec,
  }) async {
    final origin = getOrigin();
    if (origin == null || origin.isEmpty) {
      return const NeurosimHandoffPreparation.unavailable();
    }
    if (spec.trim().isEmpty) {
      return const NeurosimHandoffPreparation.emptySpec();
    }

    final importContract = await apiClient.prepareNeurosimHandoff(spec);
    final target = NeurosimHandoff.buildTarget(
      importContract: importContract,
      origin: origin,
    );
    if (target == null) {
      return const NeurosimHandoffPreparation.emptySpec();
    }

    return NeurosimHandoffPreparation.ready(target);
  }
}
