import 'package:flutter/material.dart';

class StepCard extends StatelessWidget {
  const StepCard({
    super.key,
    required this.stepName,
    required this.frameBuilder,
    required this.child,
  });

  final String stepName;
  final Widget Function({required Widget child}) frameBuilder;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return frameBuilder(child: child);
  }
}
