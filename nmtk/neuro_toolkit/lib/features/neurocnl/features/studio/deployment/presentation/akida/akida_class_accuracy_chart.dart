import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/services/studio_akida_deploy_service.dart';

/// Per-class accuracy chart for a completed Akida benchmark.

class AkidaClassAccuracyChart extends StatelessWidget {
  const AkidaClassAccuracyChart({super.key, required this.results});

  final List<StudioAkidaClassResult> results;

  static String _formatAccuracy(double fraction) =>
      '${(fraction * 100).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Accuracy by class',
          style: textStyles.titleSmall.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        for (final result in results) ...[
          Builder(
            builder: (context) {
              final name = result.labelName.isEmpty
                  ? 'Class ${result.label}'
                  : result.labelName;
              final weak = result.accuracy != null && result.accuracy! < 0.8;
              return Semantics(
                label:
                    '$name, ${result.correct} of ${result.support} correct'
                    '${weak ? ', below 80 percent' : ''}',
                child: Row(
                  children: [
                    // Flexes with the panel: fixed widths ellipsised class
                    // names at every viewport, including a maximised window.
                    Flexible(
                      flex: 3,
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: textStyles.labelSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: LinearProgressIndicator(
                        value: result.accuracy ?? 0,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(
                          NmtkShellTokens.of(context).radiusSm,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // A weak class is flagged by an icon as well as by colour,
                    // so it survives greyscale and colour-vision deficiency.
                    if (weak) ...[
                      Icon(
                        ZetaIcons.warning,
                        size: 14,
                        color: colors.mainNegative,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      flex: 4,
                      child: Text(
                        result.accuracy == null
                            ? 'No samples'
                            : '${_formatAccuracy(result.accuracy!)}  '
                                  '${result.correct}/${result.support}',
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: textStyles.labelSmall.copyWith(
                          color: weak
                              ? colors.mainNegative
                              : colors.mainDefault,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
