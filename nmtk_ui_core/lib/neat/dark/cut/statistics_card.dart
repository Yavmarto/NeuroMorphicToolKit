import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_card_header.dart';
import 'package:nmtk_ui_core/neat/dark/cut/statistic_row.dart';

/// "Statistic" card listing four stacked [StatisticRow]s.
class StatisticsCard extends StatelessWidget {
  const StatisticsCard({super.key});

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
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusSm,
          ),
        ),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 24,
        children: [
          DarkCardHeader(title: 'Statistic', iconColor: Color(0xFFFFBC99)),
          StatisticRow(
            value: '\$31,092',
            label: 'Sales',
            change: '4.2%',
            positive: true,
          ),
          StatisticRow(
            value: '\$29,128',
            label: 'Marketing',
            change: '2.1%',
            positive: true,
          ),
          StatisticRow(
            value: '\$8,094',
            label: 'Purchase',
            change: '1.4%',
            positive: false,
          ),
          StatisticRow(
            value: '\$18,891',
            label: 'Return',
            change: '1.9%',
            positive: true,
          ),
        ],
      ),
    );
  }
}
