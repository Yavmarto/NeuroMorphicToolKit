import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';

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
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        trainable ? 'Training' : 'Deploy only',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: trainable ? colors.mainPositive : colors.mainSubtle,
        ),
      ),
    );
  }
}
