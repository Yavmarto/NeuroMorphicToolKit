import 'package:flutter/material.dart';
import 'workout_stat.dart';

/// Bottom-of-page workout summary tile: three [WorkoutStat]s side by side.
class WorkoutStatsCard extends StatelessWidget {
  const WorkoutStatsCard({super.key});

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
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          WorkoutStat(iconBg: Color(0x33FFBC99), value: '380 cal', label: 'Burned'),
          WorkoutStat(iconBg: Color(0x337CDBA2), value: '80 kg', label: 'Lifted'),
          WorkoutStat(iconBg: Color(0x4CCABDFE), value: '32 min', label: 'Duration'),
        ],
      ),
    );
  }
}
