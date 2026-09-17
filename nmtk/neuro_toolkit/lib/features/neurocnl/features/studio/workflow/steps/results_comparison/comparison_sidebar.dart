import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/workflow_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/activity_comparison_data.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/platform_summary.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_comparison/activity_heatmap.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_comparison/support.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_comparison/table_data_row.dart';

class ComparisonSidebar extends StatefulWidget {
  const ComparisonSidebar({
    super.key,
    required this.summaries,
    required this.colors,
    this.activityComparison,
  });

  final List<PlatformSummary> summaries;
  final ZetaColors colors;
  final ActivityComparisonData? activityComparison;

  @override
  State<ComparisonSidebar> createState() => _ComparisonSidebarState();
}

class _ComparisonSidebarState extends State<ComparisonSidebar> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final hasActivity = widget.activityComparison != null;
    return Container(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppTheme.border)),
        color: AppTheme.surface,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasActivity) ...[
            Row(
              children: [
                SidebarTab(
                  label: 'Metrics',
                  selected: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                const SizedBox(width: 8),
                SidebarTab(
                  label: 'Activity',
                  selected: _tab == 1,
                  onTap: () => setState(() => _tab = 1),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ] else ...[
            Text(
              'All Platforms',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
          ],
          if (_tab == 0 || !hasActivity) ...[
            const TableHeaderRow(),
            const Divider(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < widget.summaries.length; i++) ...[
                      TableDataRow(
                        summary: widget.summaries[i],
                        color: platformColor(i, widget.colors),
                      ),
                      if (i < widget.summaries.length - 1)
                        const Divider(height: 8),
                    ],
                  ],
                ),
              ),
            ),
          ] else
            Expanded(
              child: ActivityHeatmap(
                data: widget.activityComparison!,
                colors: widget.colors,
              ),
            ),
        ],
      ),
    );
  }
}
