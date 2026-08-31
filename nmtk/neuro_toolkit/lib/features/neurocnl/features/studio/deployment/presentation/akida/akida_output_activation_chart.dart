import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Raw output activation chart from one Akida inference.

class AkidaOutputActivationChart extends StatelessWidget {
  const AkidaOutputActivationChart({super.key, required this.outputs});

  final List<double> outputs;

  static String _formatActivation(double value) => value.toStringAsFixed(3);

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    final indexed = <MapEntry<int, double>>[
      for (var index = 0; index < outputs.length; index++)
        MapEntry(index, outputs[index]),
    ]..sort((a, b) => b.value.compareTo(a.value));
    final visible = indexed.take(10).toList(growable: false);
    final values = visible.map((entry) => entry.value);
    final minimum = values.isEmpty ? 0.0 : values.reduce(math.min);
    final maximum = values.isEmpty ? 0.0 : values.reduce(math.max);
    final range = maximum - minimum;

    if (visible.isEmpty) {
      return Text(
        'This runtime did not return output activations.',
        style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Raw output activations',
          style: textStyles.titleSmall.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Bars are scaled within this sample. Values are raw activations, '
          'not probabilities.',
          style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
        ),
        const SizedBox(height: 12),
        for (final entry in visible) ...[
          Semantics(
            label:
                'Class ${entry.key}, raw activation ${_formatActivation(entry.value)}',
            child: Row(
              children: [
                SizedBox(
                  width: 58,
                  child: Text(
                    'Class ${entry.key}',
                    style: textStyles.labelSmall,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    value: range <= 0 ? 1 : (entry.value - minimum) / range,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(
                      NmtkShellTokens.of(context).radiusSm,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 76,
                  child: Text(
                    _formatActivation(entry.value),
                    textAlign: TextAlign.end,
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
