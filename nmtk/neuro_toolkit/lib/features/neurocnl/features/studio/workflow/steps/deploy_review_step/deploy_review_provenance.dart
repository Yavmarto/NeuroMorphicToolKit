library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';

class DeployReviewProvenance extends ConsumerWidget {
  const DeployReviewProvenance({super.key, required this.target});

  final String target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget? badge = switch (target) {
      'akida' => switch (ref.watch(studioAkidaDeployProvider)) {
        final akida when akida.deploymentJob != null => akidaProvenanceBadge(
          akida.hardwareVerified,
        ),
        _ => null,
      },
      'pynq' => switch (ref.watch(studioPynqDeployProvider).deployAck) {
        final ack? => pynqProvenanceBadge(ack),
        _ => null,
      },
      _ => null,
    };
    if (badge == null) return const SizedBox.shrink();
    return Align(alignment: Alignment.centerLeft, child: badge);
  }
}
