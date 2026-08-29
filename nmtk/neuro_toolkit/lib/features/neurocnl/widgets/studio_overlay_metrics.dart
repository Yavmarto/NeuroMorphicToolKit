import 'package:flutter/widgets.dart';

/// Passes stepper geometry from the studio layout down to canvas overlays
/// so panels can position themselves below the floating stepper bar without
/// hardcoding its height.
class StudioOverlayMetrics extends InheritedWidget {
  const StudioOverlayMetrics({
    super.key,
    required this.stepperBottom,
    this.readableContentBottom = 0,
    this.belowStepperHeaderTop = 0,
    required super.child,
  });

  /// Y-offset (in logical pixels) at which the floating stepper bar ends.
  final double stepperBottom;

  /// Y-offset used by readable, non-canvas content below the compact header.
  final double readableContentBottom;

  /// Y-offset for a per-step header row (load buttons, target picker, view
  /// switch) that sits directly below the stepper. Single source of truth so
  /// Setup, Deploy, and Run all sit the same distance under the stepper.
  final double belowStepperHeaderTop;

  static StudioOverlayMetrics? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StudioOverlayMetrics>();

  @override
  bool updateShouldNotify(StudioOverlayMetrics old) =>
      old.stepperBottom != stepperBottom ||
      old.readableContentBottom != readableContentBottom ||
      old.belowStepperHeaderTop != belowStepperHeaderTop;
}
