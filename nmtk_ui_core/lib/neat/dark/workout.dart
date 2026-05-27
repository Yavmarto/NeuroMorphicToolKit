import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'cut/dark_status_bar.dart';
import 'cut/dark_top_bar.dart';
import 'cut/workout_widgets.dart';

class NeatWorkOut extends StatelessWidget {
  @Preview(name: 'Neat Dark – Workout', group: 'Neat Dark Pages', size: Size(375, 1072))
  const NeatWorkOut({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 375,
          height: 1072,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
          child: const Stack(
            children: [
              Positioned(left: 0, top: 0, child: DarkStatusBar()),
              Positioned(left: 0, top: 44, child: DarkTopBar()),
              Positioned(left: 16, top: 156, child: GainWeightCard()),
              Positioned(left: 16, top: 648, child: WorkoutOverviewCard()),
              Positioned(left: 16, top: 906, child: WorkoutStatsCard()),
            ],
          ),
        ),
      ],
    );
  }
}
