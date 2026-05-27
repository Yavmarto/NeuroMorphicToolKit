import 'package:flutter/material.dart';
import 'weight_stat.dart';
import 'workout_stat_item.dart';

/// Three-column section inside [GainWeightCard] showing current vs target
/// weight plus the gained/left summary.
class WeightProgressSection extends StatelessWidget {
  const WeightProgressSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: const [
        WeightStat(value: '66', unit: 'Kg', label: 'Current'),
        WeightStat(value: '70', unit: 'Kg', label: 'Target'),
        Column(spacing: 4, children: [
          WorkoutStatItem(value: '+ 3.9 kg', label: 'Gained'),
          WorkoutStatItem(value: '1.4 kg', label: 'Left'),
        ]),
      ],
    );
  }
}
