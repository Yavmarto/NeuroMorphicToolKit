import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/services/studio_akida_deploy_service.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart';

class AkidaLayerActivityList extends StatelessWidget {
  const AkidaLayerActivityList({super.key, required this.layers});

  final List<LayerSpikeStats> layers;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    final maximum = layers.fold<int>(
      0,
      (current, layer) => math.max(current, layer.nzSpikes),
    );
    final layerLabels = numberLayerLabels(layers.map((layer) => layer.name));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Layer activity',
          style: textStyles.titleSmall.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Aggregate non-zero spike counts from this inference. Per-neuron '
          'timing traces are not available from Akida.',
          style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
        ),
        const SizedBox(height: 12),
        for (final (index, layer) in layers.indexed) ...[
          Semantics(
            label: '${layerLabels[index]}, ${layer.nzSpikes} non-zero spikes',
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    layerLabels[index],
                    overflow: TextOverflow.ellipsis,
                    style: textStyles.labelSmall,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: LinearProgressIndicator(
                    value: maximum == 0 ? 0 : layer.nzSpikes / maximum,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(
                      NmtkShellTokens.of(context).radiusSm,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  flex: 2,
                  child: Text(
                    '${layer.nzSpikes} spikes',
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: textStyles.labelSmall.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
