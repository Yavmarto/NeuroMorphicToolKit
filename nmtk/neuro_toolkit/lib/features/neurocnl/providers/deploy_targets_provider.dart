import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/deploy_preview_result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';

/// Per-backend node-support metadata for the Hardware Deployment dropdown.
final deployTargetsProvider = FutureProvider<List<DeployTargetInfo>>((
  ref,
) async {
  final api = ref.read(apiClientProvider);
  return api.getDeployTargets();
});

/// Side-effect-free codegen preview for a given (spec, target) pair.
final deployPreviewProvider =
    FutureProvider.family<DeployPreviewResult, ({String spec, String target})>((
      ref,
      params,
    ) async {
      final api = ref.read(apiClientProvider);
      return api.previewDeployTarget(params.spec, params.target);
    });
