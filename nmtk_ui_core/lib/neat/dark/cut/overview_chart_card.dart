import 'package:flutter/material.dart' hide FilterChip;
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_card_header.dart';
import 'package:nmtk_ui_core/neat/dark/cut/download_chip.dart';
import 'package:nmtk_ui_core/neat/dark/cut/filter_chip.dart';
import 'package:nmtk_ui_core/neat/dark/cut/overview_spend_row.dart';

/// "Overview" chart card with a Monthly filter chip, a Download chip and two
/// summary spend rows.
class OverviewChartCard extends StatelessWidget {
  const OverviewChartCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 343,
      padding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
        ),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 24,
        children: [
          DarkCardHeader(title: 'Overview', iconColor: Color(0xFFCABDFE)),
          Row(spacing: 16, children: [
            FilterChip(label: 'Monthly'),
            DownloadChip(),
          ]),
          SizedBox(height: 120),
          OverviewSpendRow(label: 'Avg monthly spend', value: '\$820.00', change: '1.2%', positive: true),
          OverviewSpendRow(label: 'Spent this month', value: '\$440.00', change: '1.4%', positive: false),
        ],
      ),
    );
  }
}
