import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/activity_comparison_data.dart';

class ActivityHeatmap extends StatelessWidget {
  const ActivityHeatmap({super.key, required this.data, required this.colors});

  final ActivityComparisonData data;
  final ZetaColors colors;

  @override
  Widget build(BuildContext context) {
    final n = data.frameworks.length;
    if (n == 0) return const SizedBox();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activity Similarity',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            'Cosine similarity of hidden-layer spikes',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          // Column headers
          Row(
            children: [
              const SizedBox(width: 56),
              for (var c = 0; c < n; c++)
                Expanded(
                  child: Text(
                    _trunc(data.frameworks[c]),
                    style: Theme.of(context).textTheme.labelSmall,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var r = 0; r < n; r++)
            Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    _trunc(data.frameworks[r]),
                    style: Theme.of(context).textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (var c = 0; c < n; c++)
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        margin: const EdgeInsets.all(1),
                        color: Color.lerp(
                          Colors.white,
                          colors.mainPrimary,
                          data.matrix[r][c].clamp(0.0, 1.0),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          data.matrix[r][c].toStringAsFixed(2),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: data.matrix[r][c] > 0.6
                                ? Zeta.of(context).colors.mainInverse
                                : Zeta.of(context).colors.mainDefault,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static String _trunc(String s) => s.length > 9 ? '${s.substring(0, 8)}…' : s;
}
