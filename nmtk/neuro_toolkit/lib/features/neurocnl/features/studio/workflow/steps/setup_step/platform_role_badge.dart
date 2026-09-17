import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class PlatformRoleBadge extends StatelessWidget {
  const PlatformRoleBadge({super.key, required this.targetId});

  final String targetId;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final trainable = targetIsTrainable(targetId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: trainable ? colors.surfacePositiveSubtle : colors.surfaceHover,
        borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
      ),
      child: Text(
        trainable ? 'Training' : 'Deploy only',
        style: Zeta.of(context).textStyles.labelSmall.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: trainable ? colors.mainPositive : colors.mainSubtle,
        ),
      ),
    );
  }
}
