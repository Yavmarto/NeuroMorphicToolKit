library;

import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/deploy_review_compare_pane.dart';

class DeployReviewCompareBody extends StatelessWidget {
  const DeployReviewCompareBody({super.key, required this.targets});

  final List<String> targets;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < targets.length; i++) ...[
          if (i > 0) const VerticalDivider(width: 24),
          Expanded(child: DeployReviewComparePane(target: targets[i])),
        ],
      ],
    );
  }
}
