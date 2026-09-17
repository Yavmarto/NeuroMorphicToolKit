import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/platform_summary.dart';

class TableDataRow extends StatelessWidget {
  const TableDataRow({super.key, required this.summary, required this.color});

  final PlatformSummary summary;
  final Color color;

  @override
  Widget build(BuildContext outerContext) {
    final label = targetLabel(summary.platformId);
    final valueStyle = Theme.of(
      outerContext,
    ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600);
    final accStr = summary.bestAccuracy == null
        ? '—'
        : '${(summary.bestAccuracy! * 100).toStringAsFixed(1)}%';
    final lossStr = summary.bestLoss == double.infinity
        ? '—'
        : summary.bestLoss.toStringAsFixed(4);
    final finalLossStr = summary.finalLoss == double.infinity
        ? '—'
        : summary.finalLoss.toStringAsFixed(4);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(outerContext).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(accStr, style: valueStyle, textAlign: TextAlign.end),
          ),
          Expanded(
            flex: 2,
            child: Text(lossStr, style: valueStyle, textAlign: TextAlign.end),
          ),
          Expanded(
            flex: 2,
            child: Text(
              finalLossStr,
              style: valueStyle,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
