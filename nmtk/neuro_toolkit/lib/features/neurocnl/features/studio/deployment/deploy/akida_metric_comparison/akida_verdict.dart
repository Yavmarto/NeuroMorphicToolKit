library;

import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/akida_workspace/support.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/akida_metric_comparison/support.dart';

class AkidaVerdict extends StatelessWidget {
  const AkidaVerdict({
    super.key,
    required this.hardwareAccuracy,
    required this.baselineLabel,
    required this.deltaPp,
    required this.latencyMs,
    required this.totalSamples,
  });

  final double hardwareAccuracy;
  final String? baselineLabel;
  final double? deltaPp;
  final double? latencyMs;
  final int? totalSamples;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    final tokens = NmtkShellTokens.of(context);
    final withinTolerance =
        deltaPp == null || deltaPp! >= -kAccuracyTolerancePp;
    final accent = withinTolerance ? tokens.healthyColor : tokens.warningColor;

    final scope = totalSamples != null && totalSamples! > 0
        ? ' across $totalSamples samples'
        : '';
    final comparison = deltaPp == null || baselineLabel == null
        ? 'No pre-conversion baseline to compare against.'
        : deltaPp! >= 0
        ? '${_formatPp(deltaPp!)} above $baselineLabel'
              '${withinTolerance ? '' : ' — worth a look'}.'
        : '${_formatPp(deltaPp!.abs())} below $baselineLabel'
              '${withinTolerance ? ' — within tolerance' : ' — worth a look'}.';
    final speed = latencyMs == null
        ? ''
        : ' ${metricValue('latency_ms', latencyMs!)} per sample.';

    return Semantics(
      container: true,
      label:
          'Hardware verdict. '
          '${formatAccuracy(hardwareAccuracy)} on card$scope. '
          '$comparison$speed',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceHover,
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'On card$scope',
                style: textStyles.labelSmall.copyWith(color: colors.mainSubtle),
              ),
              const SizedBox(height: 4),
              Text(
                formatAccuracy(hardwareAccuracy),
                style: textStyles.displaySmall.copyWith(
                  fontWeight: FontWeight.w700,
                  color: accent,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$comparison$speed',
                style: textStyles.bodySmall.copyWith(color: colors.mainDefault),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatPp(double value) => '${value.toStringAsFixed(2)} pp';
}
