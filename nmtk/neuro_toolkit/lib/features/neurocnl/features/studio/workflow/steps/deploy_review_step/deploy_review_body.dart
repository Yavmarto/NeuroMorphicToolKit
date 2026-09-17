library;

import 'package:flutter/widgets.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/support.dart';

class DeployReviewBody extends StatelessWidget {
  const DeployReviewBody({super.key, required this.selectedTarget});

  final String selectedTarget;

  @override
  Widget build(BuildContext context) => deployReviewTargetBody(selectedTarget);
}
