library;

import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/widgets/deploy/deploy_layout.dart';

class StudioStandardDeployPage extends StatelessWidget {
  const StudioStandardDeployPage({
    super.key,
    required this.title,
    required this.inference,
    required this.setup,
    this.isCompact = false,
  });

  final String title;
  final Widget inference;
  final Widget setup;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return NmtkDeployLayout(
      title: title,
      inference: inference,
      setup: setup,
      isCompact: isCompact,
    );
  }
}
