import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/models/studio_pipeline_steps.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/pipeline_stage_area/step_card.dart';

class SplitStageView extends StatelessWidget {
  const SplitStageView({
    super.key,
    required this.activeStep,
    required this.splitStep,
    required this.stepBuilder,
    required this.frameBuilder,
    this.canvasStepNames = const <String>{},
    this.contentTopPad = 0.0,
  });

  final String activeStep;
  final String splitStep;
  final Widget Function(int index) stepBuilder;
  final Widget Function({required Widget child}) frameBuilder;
  final Set<String> canvasStepNames;
  final double contentTopPad;

  @override
  Widget build(BuildContext context) {
    // Always render earlier step on left.
    final normalizedActiveStep = normalizeStudioPipelineStep(activeStep);
    final normalizedSplitStep = normalizeStudioPipelineStep(
      splitStep,
      fallback: normalizedActiveStep,
    );
    final aIdx = indexOfStudioPipelineStep(normalizedActiveStep);
    final sIdx = indexOfStudioPipelineStep(
      normalizedSplitStep,
      fallback: normalizedActiveStep,
    );
    final leftStep = aIdx <= sIdx ? normalizedActiveStep : normalizedSplitStep;
    final rightStep = aIdx <= sIdx ? normalizedSplitStep : normalizedActiveStep;
    final leftIndex = indexOfStudioPipelineStep(leftStep);
    final rightIndex = indexOfStudioPipelineStep(rightStep, fallback: leftStep);

    Widget leftChild = stepBuilder(leftIndex);
    Widget rightChild = stepBuilder(rightIndex);
    if (contentTopPad > 0) {
      if (!canvasStepNames.contains(leftStep)) {
        leftChild = Padding(
          padding: EdgeInsets.only(top: contentTopPad),
          child: leftChild,
        );
      }
      if (!canvasStepNames.contains(rightStep)) {
        rightChild = Padding(
          padding: EdgeInsets.only(top: contentTopPad),
          child: rightChild,
        );
      }
    }

    return Row(
      children: [
        Expanded(
          child: StepCard(
            stepName: leftStep,
            frameBuilder: frameBuilder,
            child: leftChild,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StepCard(
            stepName: rightStep,
            frameBuilder: frameBuilder,
            child: rightChild,
          ),
        ),
      ],
    );
  }
}
