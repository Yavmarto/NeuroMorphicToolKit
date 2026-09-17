import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/workflow_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_step/support.dart' show rdbuColor;

class NeuronDetailSheet extends StatelessWidget {
  final int neuronIndex;
  final Float32List weights;
  final int side;
  final double vmax;
  final int nInputs;

  const NeuronDetailSheet({
    super.key,
    required this.neuronIndex,
    required this.weights,
    required this.side,
    required this.vmax,
    required this.nInputs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = Float32List.fromList(weights.toList()..sort());
    final minW = sorted.first;
    final maxW = sorted.last;
    double sum = 0;
    for (final w in weights) {
      sum += w;
    }
    final mean = sum / weights.length;
    double variance = 0;
    for (final w in weights) {
      variance += (w - mean) * (w - mean);
    }
    final std = variance > 0 ? (variance / weights.length) : 0.0;
    // L1 sparsity: fraction of weights whose absolute value < 5% of vmax
    final threshold = vmax.abs() * 0.05;
    final sparse =
        weights.where((w) => w.abs() < threshold).length / weights.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(NmtkShellTokens.of(context).radiusLg),
          ),
        ),
        child: Column(
          children: [
            // drag handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(
                  NmtkShellTokens.of(context).radiusChip,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Neuron $neuronIndex',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$nInputs inputs · $side×$side',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Large tile
            SizedBox(
              width: 200,
              height: 200,
              child: CustomPaint(
                painter: WeightTilePainter(
                  weights: weights,
                  side: side,
                  vmax: vmax,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Colour scale bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  Container(
                    height: 12,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          rdbuColor(-vmax, vmax),
                          rdbuColor(0, vmax),
                          rdbuColor(vmax, vmax),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(
                        NmtkShellTokens.of(context).radiusChip,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        vmax.toStringAsFixed(3),
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
                      ),
                      Text(
                        '0',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
                      ),
                      Text(
                        '+${vmax.toStringAsFixed(3)}',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Stats grid
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  StatRow('Min weight', minW.toStringAsFixed(4)),
                  StatRow('Max weight', maxW.toStringAsFixed(4)),
                  StatRow('Mean', mean.toStringAsFixed(4)),
                  StatRow('Std dev', std.toStringAsFixed(4)),
                  StatRow(
                    'Near-zero (< 5% vmax)',
                    '${(sparse * 100).toStringAsFixed(1)}%',
                  ),
                  StatRow(
                    '|max| dominance',
                    (maxW.abs() / (vmax.abs() + 1e-9)).toStringAsFixed(3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
