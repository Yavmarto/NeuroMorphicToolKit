import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/services/studio_akida_deploy_service.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';

class AkidaBenchmarkResultView extends StatelessWidget {
  const AkidaBenchmarkResultView({super.key, required this.snapshot});

  final StudioAkidaBenchmarkSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    if (snapshot == null) {
      return Text(
        'Run a benchmark to compare Akida accuracy, latency, throughput, and '
        'available power measurements with source and simulator baselines.',
        style: textStyles.bodyMedium.copyWith(color: colors.mainSubtle),
      );
    }

    final job = snapshot!.job;
    final classes = job.classResults ?? const <StudioAkidaClassResult>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The page header carries the hardware-versus-simulator claim; this
        // view says only what the page header cannot.
        Text(
          'This report measures inference. Akida training is not supported '
          'by this workflow.',
          style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
        ),
        const SizedBox(height: 20),
        AkidaMetricComparison(job: job),
        const SizedBox(height: 24),
        if (classes.isNotEmpty)
          AkidaClassAccuracyChart(results: classes)
        else
          Text(
            'This runtime did not return per-class benchmark results.',
            style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
          ),
      ],
    );
  }
}
