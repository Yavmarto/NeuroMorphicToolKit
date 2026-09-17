library;

import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/deploy_review_provenance.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/support.dart';

class DeployReviewComparePane extends StatelessWidget {
  const DeployReviewComparePane({super.key, required this.target});

  final String target;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                targetLabel(target),
                style: Zeta.of(
                  context,
                ).textStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DeployReviewProvenance(target: target),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: deployReviewTargetBody(target)),
      ],
    );
  }
}
