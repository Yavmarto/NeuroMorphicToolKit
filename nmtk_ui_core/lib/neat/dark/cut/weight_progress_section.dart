import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/neat/dark/cut/weight_stat.dart';
import 'package:nmtk_ui_core/neat/dark/cut/workout_stat_item.dart';

/// Three-column section inside [GainWeightCard] showing current vs target
/// weight plus the gained/left summary.
class WeightProgressSection extends StatelessWidget {
  const WeightProgressSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        WeightStat(value: '66', unit: 'Kg', label: 'Current'),
        WeightStat(value: '70', unit: 'Kg', label: 'Target'),
        Column(
          spacing: 4,
          children: [
            WorkoutStatItem(value: '+ 3.9 kg', label: 'Gained'),
            WorkoutStatItem(value: '1.4 kg', label: 'Left'),
          ],
        ),
      ],
    );
  }
}
