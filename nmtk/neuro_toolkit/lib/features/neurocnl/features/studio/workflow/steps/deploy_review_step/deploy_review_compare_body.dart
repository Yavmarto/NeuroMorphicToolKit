library;

import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/deploy_review_compare_pane.dart';

class DeployReviewCompareBody extends StatelessWidget {
  const DeployReviewCompareBody({super.key, required this.targets});

  final List<String> targets;

  @override
  Widget build(BuildContext context) {
    // Side-by-side columns collapse below usable width once 2+ targets share
    // a 375-844px viewport, so narrow layouts stack panes instead — each pane
    // keeps the bounded height its result body needs (see
    // `deployReviewTargetBody`) while the outer list scrolls.
    if (MediaQuery.sizeOf(context).width < 600) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final paneHeight = constraints.hasBoundedHeight
              ? (constraints.maxHeight * 0.75).clamp(320.0, 640.0)
              : 480.0;
          return ListView.separated(
            itemCount: targets.length,
            separatorBuilder: (_, _) => const Divider(height: 24),
            itemBuilder: (context, i) => SizedBox(
              height: paneHeight,
              child: DeployReviewComparePane(target: targets[i]),
            ),
          );
        },
      );
    }
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
