import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/services/studio_akida_deploy_service.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/studio_shared.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';

class AkidaSampleResultView extends StatelessWidget {
  const AkidaSampleResultView({super.key, required this.snapshot});

  final StudioAkidaSampleSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final snapshot = this.snapshot;
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    if (snapshot == null) {
      return Text(
        'Run a sample to inspect its prediction, output activations, and '
        'available hardware activity.',
        style: textStyles.bodyMedium.copyWith(color: colors.mainSubtle),
      );
    }

    final prediction = snapshot.prediction;
    final telemetry = prediction.telemetry.entries
        .where((entry) => entry.value != null)
        .toList(growable: false);
    final layers = prediction.layerSpikes ?? const <LayerSpikeStats>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioPhaseBanner(
          label: predictionSummary(prediction),
          tone: prediction.label == null
              ? NmtkTone.neutral
              : prediction.label == prediction.prediction
              ? NmtkTone.success
              : NmtkTone.warning,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            Text('Sample ${prediction.sampleIndex ?? '—'}'),
            Text('Runtime ${snapshot.provenance.runtimeTarget}'),
            Text('Top outputs ${topOutputs(prediction.outputs)}'),
          ],
        ),
        const SizedBox(height: 16),
        AkidaOutputActivationChart(outputs: prediction.outputs),
        if (layers.isNotEmpty) ...[
          const SizedBox(height: 16),
          AkidaLayerActivityList(layers: layers),
        ],
        if (telemetry.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Runtime telemetry',
            style: textStyles.titleSmall.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in telemetry)
                NmtkInfoChip(
                  icon: ZetaIcons.analytics,
                  label: entry.key,
                  value: '${entry.value}',
                ),
            ],
          ),
        ],
      ],
    );
  }
}
