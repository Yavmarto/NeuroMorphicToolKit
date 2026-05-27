import 'package:flutter/material.dart' hide FilterChip;
import 'dark_card_header.dart';
import 'download_chip.dart';
import 'filter_chip.dart';
import 'overview_spend_row.dart';

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
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 24,
        children: [
          const DarkCardHeader(title: 'Overview', iconColor: Color(0xFFCABDFE)),
          Row(spacing: 16, children: [
            const FilterChip(label: 'Monthly'),
            DownloadChip(),
          ]),
          const SizedBox(height: 120),
          const OverviewSpendRow(label: 'Avg monthly spend', value: '\$820.00', change: '1.2%', positive: true),
          const OverviewSpendRow(label: 'Spent this month', value: '\$440.00', change: '1.4%', positive: false),
        ],
      ),
    );
  }
}
