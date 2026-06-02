import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_status_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_top_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/tracker_widgets.dart';

class NeatTracker extends StatelessWidget {
  @Preview(
    name: 'Neat Dark – Tracker',
    group: 'Neat Dark Pages',
    size: Size(375, 1217),
  )
  const NeatTracker({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 375,
          height: 1217,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
          child: const Stack(
            children: [
              Positioned(left: 0, top: 0, child: DarkStatusBar()),
              Positioned(left: 0, top: 44, child: DarkTopBar()),
              Positioned(left: 16, top: 156, child: ProgressCard()),
              Positioned(left: 16, top: 292, child: CaloriesCard()),
              Positioned(
                left: 195,
                top: 292,
                child: TrackerSmallStatCard(
                  value: '16',
                  label: 'Glass of Water',
                  iconBg: Color(0xFFE0EBFA),
                ),
              ),
              Positioned(
                left: 195,
                top: 408,
                child: TrackerSmallStatCard(
                  value: '10km',
                  label: 'Step to Walk',
                  iconBg: Color(0xFFE7FFF2),
                ),
              ),
              Positioned(left: 16, top: 524, child: ActivitiesCard()),
              Positioned(
                left: 16,
                top: 1030,
                child: ActivityTypeCard(
                  label: 'Cycling',
                  sublabel: '12,000 km',
                ),
              ),
              Positioned(
                left: 195,
                top: 1030,
                child: ActivityTypeCard(label: 'Heart', sublabel: '100 bpm'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
