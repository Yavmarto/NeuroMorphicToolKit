import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_status_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_top_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/overview_widgets.dart';

class NeatOverview extends StatelessWidget {
  @Preview(name: 'Neat Dark – Overview', group: 'Neat Dark Pages', size: Size(375, 1099))
  const NeatOverview({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 375,
          height: 1099,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
          child: const Stack(
            children: [
              Positioned(left: 0, top: 0, child: DarkStatusBar()),
              Positioned(left: 0, top: 44, child: DarkTopBar()),
              Positioned(left: 16, top: 156, child: OverviewChartCard()),
              Positioned(left: 16, top: 539, child: StatisticsCard()),
              Positioned(left: 16, top: 867, child: TargetCard(value: '72%', label: 'Target reached this month')),
              Positioned(left: 16, top: 981, child: TargetCard(value: '89%', label: 'Engagement rate this month')),
            ],
          ),
        ),
      ],
    );
  }
}
