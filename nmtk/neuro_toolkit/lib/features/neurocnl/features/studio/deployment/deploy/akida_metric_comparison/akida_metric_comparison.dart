import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/services/studio_akida_deploy_service.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/akida_workspace/support.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/akida_metric_comparison/akida_verdict.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/akida_metric_comparison/support.dart';

class AkidaMetricComparison extends StatelessWidget {
  const AkidaMetricComparison({super.key, required this.job});

  final StudioAkidaModelJob job;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    final baselineEntry = _baselineEntry(job.metrics);
    final hardware = job.metrics['akida_accuracy'];
    final delta = hardware != null && baselineEntry != null
        ? (hardware - baselineEntry.value) * 100
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hardware != null)
          AkidaVerdict(
            hardwareAccuracy: hardware,
            baselineLabel: baselineEntry == null
                ? null
                : _baselineShortLabel(baselineEntry.key),
            deltaPp: delta,
            latencyMs: job.metrics['latency_ms'],
            totalSamples: job.totalSamples,
          ),
        if (hardware != null) const SizedBox(height: 20),
        Text(
          'Hardware versus baseline',
          style: textStyles.titleSmall.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final metric in orderedMetrics(job.metrics))
              SizedBox(
                width: kMetricTileWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceHover,
                    borderRadius: BorderRadius.circular(
                      NmtkShellTokens.of(context).radiusMd,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metricLabel(
                            metric.key,
                            totalSamples: job.totalSamples,
                          ),
                          style: textStyles.labelSmall.copyWith(
                            color: colors.mainSubtle,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          metricValue(metric.key, metric.value),
                          style: textStyles.titleMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// The closest pre-hardware accuracy to compare against, nearest first.
  MapEntry<String, double>? _baselineEntry(Map<String, double> metrics) {
    for (final key in const <String>[
      'akida_sim_accuracy',
      'snntorch_accuracy',
      'pytorch_accuracy',
      'onnx_accuracy',
    ]) {
      final value = metrics[key];
      if (value != null) return MapEntry(key, value);
    }
    return null;
  }

  String _baselineShortLabel(String key) => switch (key) {
    'akida_sim_accuracy' => 'the Akida simulator',
    'snntorch_accuracy' => 'snnTorch',
    'pytorch_accuracy' => 'PyTorch',
    'onnx_accuracy' => 'ONNX',
    _ => 'baseline',
  };
}
