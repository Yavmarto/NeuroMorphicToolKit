import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Desktop/mobile layout numbers shared by the Studio shell widgets.
class StudioLayoutMetrics {
  const StudioLayoutMetrics({
    required this.isMobile,
    required this.stepperHeight,
    required this.stepperMargin,
    required this.topInset,
    required this.contentTopPad,
    required this.showBelowStepperHeaderRow,
    required this.belowStepperRowHeight,
  });

  final bool isMobile;
  final double stepperHeight;
  final double stepperMargin;
  final double topInset;
  final double contentTopPad;
  final bool showBelowStepperHeaderRow;
  final double belowStepperRowHeight;

  static StudioLayoutMetrics forConstraints({
    required BoxConstraints layoutConstraints,
    required NmtkShellTokens tokens,
    required String activeStep,
  }) {
    final isMobile =
        layoutConstraints.maxWidth < NmtkShellTokens.compactBreakpoint;
    const stepperHeight = 60.0;
    const readableContentHeaderHeight = 88.0;
    final stepperMargin = tokens.compactGap;
    const topInset = 0.0;
    const belowStepperRowHeight = 56.0;
    final showBelowStepperHeaderRow = switch (activeStep) {
      'selectData' => layoutConstraints.maxWidth >= 1200,
      'deployReview' => layoutConstraints.maxWidth >= 600,
      _ => false,
    };
    final contentTopPad = isMobile
        ? 0.0
        : stepperMargin +
              readableContentHeaderHeight +
              stepperMargin +
              (showBelowStepperHeaderRow
                  ? belowStepperRowHeight + stepperMargin
                  : 0);
    return StudioLayoutMetrics(
      isMobile: isMobile,
      stepperHeight: stepperHeight,
      stepperMargin: stepperMargin,
      topInset: topInset,
      contentTopPad: contentTopPad,
      showBelowStepperHeaderRow: showBelowStepperHeaderRow,
      belowStepperRowHeight: belowStepperRowHeight,
    );
  }
}
