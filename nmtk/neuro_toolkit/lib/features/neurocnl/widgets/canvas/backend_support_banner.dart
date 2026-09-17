import 'package:flutter/material.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/deploy/backend_support_banner.dart';

class BackendSupportBanner extends StatelessWidget {
  final BackendSupport support;
  final GeneratorFidelitySummary? generatorFidelity;
  final String? title;
  final bool compact;

  const BackendSupportBanner({
    super.key,
    required this.support,
    this.generatorFidelity,
    this.title,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return NmtkBackendSupportBanner(
      verdict: support.verdict,
      backend: support.backend,
      warnings: support.warnings,
      title: title,
      compact: compact,
    );
  }
}
