import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/models/studio_pipeline_steps.dart';

import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/pipeline_stage_area/step_card.dart';

class SingleStageView extends StatelessWidget {
  const SingleStageView({
    super.key,
    required this.pageController,
    required this.stepCount,
    required this.stepBuilder,
    required this.frameBuilder,
    required this.onStepChanged,
    required this.isMobile,
    this.canvasStepNames = const <String>{},
    this.cardHPad = 4.0,
    this.contentTopPad = 0.0,
  });

  final PageController pageController;
  final int stepCount;
  final Widget Function(int index) stepBuilder;
  final Widget Function({required Widget child}) frameBuilder;
  final ValueChanged<String> onStepChanged;
  final Set<String> canvasStepNames;
  final double cardHPad;
  // ponytail: top padding applied inside non-canvas cards so content clears
  // the floating stepper while the card background fills full-screen.
  final double contentTopPad;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      physics: isMobile ? const NeverScrollableScrollPhysics() : null,
      controller: pageController,
      itemCount: stepCount,
      clipBehavior: Clip.hardEdge,
      onPageChanged: (index) {
        if (index >= 0 && index < kStudioPipelineStepNames.length) {
          onStepChanged(kStudioPipelineStepNames[index]);
        }
      },
      itemBuilder: (context, index) {
        final isCanvas = canvasStepNames.contains(
          kStudioPipelineStepNames[index],
        );
        if (isCanvas) {
          // Full-bleed: no frame, no padding — canvas fills edge-to-edge
          return stepBuilder(index);
        }
        if (contentTopPad > 0) {
          // Desktop non-canvas: full-bleed, near-black background (AppTheme.background
          // = 0xFF08090A) is clearly distinct from the navy stepper container
          // (AppTheme.surface = 0xFF0F172A) — creates the visible "slight overlap".
          // contentTopPad pushes readable content below the floating stepper.
          return ColoredBox(
            color: AppTheme.background,
            child: Padding(
              padding: EdgeInsets.only(top: contentTopPad),
              child: stepBuilder(index),
            ),
          );
        }
        // Mobile (contentTopPad == 0): card frame as before.
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: cardHPad),
          child: StepCard(
            stepName: kStudioPipelineStepNames[index],
            frameBuilder: frameBuilder,
            child: stepBuilder(index),
          ),
        );
      },
    );
  }
}
